//
//  ChargingPredictionViewController.swift
//  CanZE
//
//  Created by Roberto Sonzogni on 09/02/21.
//

import UIKit

class ChargingPredictionViewController: CanZeViewController {
    @IBOutlet var lblDebug: UILabel!

    //

    @IBOutlet var label_ChargingPrediction: UILabel!

    @IBOutlet var label_Duration: UILabel!
    @IBOutlet var label_Soc: UILabel!
    @IBOutlet var label_Range: UILabel!
    @IBOutlet var label_DcPower: UILabel!
    @IBOutlet var label_Duration_: UILabel!
    @IBOutlet var label_Soc_: UILabel!
    @IBOutlet var label_Range_: UILabel!
    @IBOutlet var label_DcPower_: UILabel!

    @IBOutlet var HeaderDC: UILabel!
    @IBOutlet var label_BatteryTemperature: UILabel!
    @IBOutlet var texttemp: UILabel!
    @IBOutlet var label_ACPower: UILabel!
    @IBOutlet var textacpwr: UILabel!
    @IBOutlet var label_StateOfCharge: UILabel!
    @IBOutlet var textsoc: UILabel!

    var battery: Battery!

    var car_soc = 5.0
    var car_soh = 100.0
    var car_bat_temp = 10.0
    var car_charger_ac_power = 22.0
    var car_status = 0
    var charging_status = 0
    var seconds_per_tick = 288 // time 100 iterations = 8 hours
    var car_range_est = 1.0

    var tim_: [String] = ["", "", "", "", "", "", "", "", "", ""]
    var soc_: [String] = ["", "", "", "", "", "", "", "", "", ""]
    var ran_: [String] = ["", "", "", "", "", "", "", "", "", ""]
    var pow_: [String] = ["", "", "", "", "", "", "", "", "", ""]

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.

        title = NSLocalizedString_("title_activity_prediction", comment: "")
        lblDebug.text = ""
        NotificationCenter.default.addObserver(self, selector: #selector(updateDebugLabel(notification:)), name: Notification.Name("updateDebugLabel"), object: nil)

        ///

        label_ChargingPrediction.text = NSLocalizedString_("label_ChargingPrediction", comment: "")

        label_Duration_.text = NSLocalizedString_("label_Duration", comment: "")
        label_Soc_.text = NSLocalizedString_("label_Soc", comment: "")
        label_Range_.text = NSLocalizedString_("label_Range", comment: "")
        label_DcPower_.text = NSLocalizedString_("label_DcPower", comment: "")

        HeaderDC.text = NSLocalizedString_("label_StateAtThisMoment", comment: "")
        label_BatteryTemperature.text = NSLocalizedString_("label_BatteryTemperature", comment: "")
        texttemp.text = "-"
        label_ACPower.text = NSLocalizedString_("label_ACPower", comment: "")
        textacpwr.text = "-"
        label_StateOfCharge.text = NSLocalizedString_("label_StateOfCharge", comment: "")
        textsoc.text = "-"

        battery = Battery()

        // set charger limit
        if Globals.shared.car == AppSettings.CAR_ZOE_R240 || Globals.shared.car == AppSettings.CAR_ZOE_R90 {
            battery.dcPowerLowerLimit = 1.0
            battery.dcPowerUpperLimit = 20.0
        }

        if Globals.shared.car == AppSettings.CAR_ZOE_Q90 || Globals.shared.car == AppSettings.CAR_ZOE_R90 {
            battery.setBatteryType(41)
        } else {
            battery.setBatteryType(22)
        }

        runPrediction()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        NotificationCenter.default.addObserver(self, selector: #selector(decoded(notification:)), name: Notification.Name("decoded"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(endQueue2), name: Notification.Name("endQueue2"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(autoInit2), name: Notification.Name("autoInit"), object: nil)

        startQueue()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        NotificationCenter.default.removeObserver(self, name: Notification.Name("decoded"), object: nil)
        NotificationCenter.default.removeObserver(self, name: Notification.Name("updateDebugLabel"), object: nil)
        NotificationCenter.default.removeObserver(self, name: Notification.Name("endQueue2"), object: nil)
        NotificationCenter.default.removeObserver(self, name: Notification.Name("autoInit"), object: nil)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
    }

    @objc func updateDebugLabel(notification: Notification) {
        let notificationObject = notification.object as? [String: String]
        DispatchQueue.main.async { [self] in
            lblDebug.text = notificationObject?["debug"]
        }
        debug((notificationObject?["debug"])!)
    }

    override func startQueue() {
        if !Globals.shared.deviceIsConnected || !Globals.shared.deviceIsInitialized {
            DispatchQueue.main.async { [self] in
                view.makeToast(NSLocalizedString_("Device not connected", comment: ""))
            }
            return
        }

        Globals.shared.queue2 = []
        Globals.shared.lastId = 0

        addField_(Sid.RangeEstimate, intervalMs: 10000) // 0x08
        addField_(Sid.AvailableChargingPower, intervalMs: 10000) // 0x01
        addField_(Sid.UserSoC, intervalMs: 10000) // 0x02
        // addField(Sid.ChargingStatusDisplay, 10000);
        addField_(Sid.AverageBatteryTemperature, intervalMs: 10000) // 0x04
        addField_(Sid.SOH, intervalMs: 10000) // 0x20

        startQueue2()
    }

    @objc func endQueue2() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [self] in
            startQueue()
        }
    }

    @objc func decoded(notification: Notification) {
        let obj = notification.object as! [String: String]
        let sid = obj["sid"]

        let val = Globals.shared.fieldResultsDouble[sid!]
        if val != nil && !val!.isNaN {
            DispatchQueue.main.async { [self] in
                switch sid {
                case Sid.AvailableChargingPower:
                    car_charger_ac_power = val!
                    car_status |= 0x01
                    if car_charger_ac_power > 1 {
                        car_status |= 0x10
                        charging_status = 1
                    } else {
                        charging_status = 0
                    }
                case Sid.UserSoC:
                    car_soc = val!
                    car_status |= 0x02
                case Sid.AverageBatteryTemperature:
                    car_bat_temp = val!
                    car_status |= 0x04
                case Sid.RangeEstimate:
                    car_range_est = val!
                    car_status |= 0x08
                // case Sid.ChargingStatusDisplay:
                //    charging_status = (fieldVal == 3) ? 1 : 0;
                //    car_status |= 0x10;
                //    break;
                case Sid.SOH:
                    car_soh = val!
                    car_status |= 0x20
                default:
                    if let f = Fields.getInstance.fieldsBySid[sid!] {
                        print("unknown sid \(sid!) \(f.name ?? "")")
                    } else {
                        print("unknown sid \(sid!)")
                    }
                }

                if car_status == 0x3f {
                    // dropDebugMessage2 (String.format(Locale.getDefault(), "go %02X", car_status));
                    runPrediction()
                    car_status = 0
                } // else {
                // dropDebugMessage2 (String.format(Locale.getDefault(), ".. %02X", car_status));
                // }
            }
        }
    }

    func runPrediction() {
        DispatchQueue.main.async { [self] in
            texttemp.text = "\(Int(car_bat_temp))°C"
            textsoc.text = "\(Int(car_soc))%"
        }
        // if there is no charging going on, erase all fields in the table
        if charging_status == 0 {
            DispatchQueue.main.async { [self] in
                textacpwr.text = "Not charging"
            }
            for t in 0 ..< 10 {
                tim_[t] = "00:00"
                soc_[t] = "-"
                ran_[t] = "-"
                pow_[t] = "-"
                updatePrediction()
            }
            return
        }

        // set the battery object to an initial state equal to the real battery (
        battery.secondsRunning = 0

        // set the State of Health
        battery.setStateOfHealth(car_soh)

        // set the internal battery temperature
        battery.setTemperature(car_bat_temp)

        // set the internal state of charge
        battery.setStateOfChargePerc(car_soc)

        // set the external maximum charger capacity

        DispatchQueue.main.async { [self] in
            textacpwr.text = "\(Int(car_charger_ac_power * 10) / 10) kW)"
        }

        battery.setChargerPower(car_charger_ac_power)

        // now start iterating over time
        var iter_at_99 = 100 // tick when the battery is full
        for t in 1 ..< 101 { // 100 ticks
            battery.iterateCharging(seconds_per_tick)
            let soc = battery.getStateOfChargePerc()
            // save the earliest tick when the battery is full
            if soc >= 99, t < iter_at_99 {
                iter_at_99 = t
            }
            // optimization
            if (t % 10) == 0 {
                tim_[t / 10] = formatTime(battery.secondsRunning)
                soc_[t / 10] = "\(Int(soc)))"
                if car_soc > 0.0 {
                    ran_[t / 10] = "\(Int(car_range_est * soc / car_soc))"
                }
                pow_[t / 10] = String(format: "%.1f", battery.getDcPower())
                updatePrediction()
            }
        }

        // adjust the tick time if neccesary. Note that this is
        // effective on th next iteration

        if iter_at_99 == 100, seconds_per_tick < 288 {
            // if we were unable to go to 99% and below 8 hours, double tick step
            seconds_per_tick *= 2
        } else if iter_at_99 > 50 {
            // if we were full after half the table size
            // do nothing
            // seconds_per_tick *= 1;
        } else if iter_at_99 > 25, seconds_per_tick > 18 {
            // if we were full after a quarter of the table size
            // and over half an hour, half the tick step
            seconds_per_tick /= 2
        } else if seconds_per_tick > 18 {
            // if we were full before or equal a quarter of the table size
            // and over half an hour, quarter the tick step
            seconds_per_tick /= 4
        }
    }

    func updatePrediction() {
        var tim = ""
        var soc = ""
        var ran = ""
        var pow = ""

        for t in 0 ..< 10 {
            tim.append("\(tim_[t])\n")
            soc.append("\(soc_[t])\n")
            ran.append("\(ran_[t])\n")
            pow.append("\(pow_[t])\n")
        }

        DispatchQueue.main.async { [self] in
            label_Duration.text = tim.trimmingCharacters(in: .whitespacesAndNewlines)
            label_Soc.text = soc.trimmingCharacters(in: .whitespacesAndNewlines)
            label_Range.text = ran.trimmingCharacters(in: .whitespacesAndNewlines)
            label_DcPower.text = pow.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func formatTime(_ t2: Int) -> String {
        // t is in seconds
        var t = t2
        t /= 60
        // t is in minutes
        return "" + format2Digit(t / 60) + ":" + format2Digit(t % 60)
    }

    func format2Digit(_ t: Int) -> String {
        return ("00\(t)").subString(from: t > 9 ? 2 : 1)
    }

    /*
     public void dropDebugMessage (final String msg) {}

     public void dropDebugMessage2 (final String msg) {
         runOnUiThread(new Runnable() {
             @Override
             public void run() {
                 TextView tv = findViewById(R.id.textDebug);
                 if (tv != null) tv.setText(msg);
             }
         });
     }
     */
}
