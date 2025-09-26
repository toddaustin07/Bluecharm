# Bluecharm Gateway SmartThings Edge Driver

This driver supports only the Bluecharm Beacon Scanner Gateway BCG04 in an MQTT configuration.  It has only been tested with the standard and Pro versions of the BC021 iBeacon Multibeacon, which supports button triggers and motion sensor.  However it can be extended to support other beacon products if users request and can perform the testing.

### What/Who is Bluecharm?

Bluecharm is a company that sells BLE beacon products that have some popularity among home automation enthusiests.  [See their website here](https://bluecharmbeacons.com/)   Products include various iBeacons as well as contact sensors, buttons, humidity & temperature sensors, and gateways.

### Why a SmartThings Edge Driver?
Bluetooth low-energy (BLE) devices can be useful features in a home automation setup.  They can be especially useful as presence sensors:  a replacement for the old and no-longer-available SmartThings presence sensor, or as a more reliable substitute for mobile device location presence within SmartThings.  An Edge driver provides a local-network-only solution for integrating BLE type devices into SmartThings.

#### MQTT
One may also wonder why MQTT is required.  The Bluecharm GCG04 Gateway does in fact also support regular wifi-based communication, however because other network apps can't initiate communication to a Smartthings hub Edge driver, it probably cannot be made to work without some hassle.  MQTT was the quickest route to getting this up and running for me and met my objective of a purely local solution.  Perhaps Matter will be supported in the future, which would make this driver obsolete.

### Features
- Supports multiple BCG04 gateways
- Supports multiple beacon devices
- Supports presence, button pushes (single/double/triple/long), and motion
- Supports TLM data if enabled on the beacon device, which provides battery, device temperature, and signal strength
- Configurable grace period to determine away/not-present condition

### Pre-requisites:
- SmartThings Hub
- Bluecharm BCG04
- Bluecharm BC021 or similar
- MQTT Broker (e.g. Mosquitto running on Raspberry Pi); server must be on the same subnet as your SmartThings hub

## Driver Install and Configuration
[Get the driver from my Test Channel here](https://bestow-regional.api.smartthings.com/invite/Q1jP7BqnNNlL)

Once the driver has been installed on your SmartThings hub, from the mobile app, perform an *Add Device / Scan nearby* and a new device will be created called "Bluecharm MQTT".  Look for this device and open it.  From its Controls screen tap the 3 vertical dot menu in the upper right corner to select device Settings.  Here, provide your MQTT Broker username & password, and its IP address (make sure you have this IP address set as static on your router so it does not change).  Save your changes, and if successful, you should see "Connected to Broker" back on the device Controls screen.  The Refresh button there can be used to force a re-connection with the broker, although this is really only needed as a last resort.

## Creating and configuring Beacon devices
From the Bluecharm MQTT device Controls screen, tap the top field "Select & Create Beacon Device".  This will display a list of known Beacon types sold by Bluecharm.  Note that only the BC021 MultiBeacon or BC021 Pro iBeacon are currently supported.  Choosing any other type will result in a "Not Supported" message back on the Controls screen.  Repeat this procedure for each iBeacon device you want to have in SmartThings.

Once a beacon type is selected, a new device will be created.  Find it, open it, and go to the device Settings screen as descibed above and configure the various fields in each SmartThings device as follows:

#### MQTT Topic Prefix
This should ordinarily not be changed, and should always contain "bluecharm/publish"

#### Gateway MAC Addresses
Note this says "Addresses" plural.  This means you can list more than one MAC address separated by commas.  You can find your BCG04 Gateway MAC address either from a label on the device itself, or by the **KGateway** app that is used to configure it.  Provide one or several MAC address representing each of your Bluecharm BCG04 Gateway(s).

---
##### A note about MAC Addresses:  These must be 6 pairs of hexadecimal characters.  They can be entered as either a continuous sequence of 12 characters or 6 pairs separated with colons.
---

#### iBeacon MAC Address
Find your BC021 MAC address either from a label on the device itself, or by the **KBeacon** app used to configure it.  You only provide one MAC address corresponding to a physical iBeacon/Multibeacon.

#### UUID
The iBeacon/Multibeacon UUID is a unique 32 hexadecimal character identifier which you will find in the **KBeacon** app configuration screens.  Carefully copy/paste this ID from the KBeacon app into the SmartThings device Settings screen so as not to make a mistake.  This ID *must* contain dashes ("-") between the UUID segments.  They are **not** optional.  Note that the UUID can optionally be uniquely configured in **Pro** iBeacon devices, so be sure you've entered the correct ID for regular advertisements.

#### NOT PRESENT Grace Period
When a gateway is no longer receiving advertisements from a BLE device, it is assumed to be out of range.  For our purposes, we assume that the device is no longer present.  However, how long to wait until you assume the device is no longer present can depend on many things including configuration settings and environment.  So this device Settings field allows the user to adjust this "grace period" anywhere from 5 seconds to 10 minutes.  The user will need to experiment with the values here to eliminate all false 'not-present' states reported for the SmartThings device.

### Gateway Configuration Notes
This assumes you are using the KGateway mobile app per the manufacturer's instructions.  
- Be sure to configure the Gateway for MQTT, providing the applicable information; I recommend a QoS of 1
- Upload interval of 1 second seems OK
- Scan parameters of 100 milliseconds seem OK
- I recommend using the BLE filter parameters to keep the gateway from spending time processing other BLE signals to maximize reliability.  Provide a MAC list of your beacon devices in this option

### Beacon Configuration Notes
This assumes you are using the KBeacon mobile app per the manufacturer's instructions.  
The settings you use will depend on what you are trying to accomplish.  My experience is limited and others may have better recommendations, but here is what I am using for basic presence purposes with an objective of optimizing beacon reliability & battery life:
```
  Advertising Interval:  5 seconds
  Transmission Power:  2-3 dBm
  Beacon Type:  for regular operation, iBeacon only (which will cover general presence, motion, and button pushes),
                but during testing and to monitor battery useage you may want to temporarily include TLM
  Trigger commmand
    Motion Trigger
      Enable trigger
      Mode:  Always advertisement
      Type:  iBeacon
      Trigger Adv Time:  15 seconds
      Trigger Adv Interval:  400 ms
      Trigger parameters -> Motion sensitivity:  20
    Button Trigger
      Enable trigger
      Mode:  Always advertisement
      Type: iBeacon
      Trigger Adv Time: 10 seconds
      Trigger Adv Interval:  2000 ms
      Trigger parameters -> Double click    Note that this follows recommendation of documentation.
                            Single clicks can too often be done accidently while banging around a purse or pocket.
```
Note that Pro configuration is a bit more complex and not covered here.  I can provide my settings upon request.

### Motion and Button Reporting
There is a 30 second cooldown period in the driver for these advertisements, which means multiple motion or button triggers received within the same 30-second window are ignored.  Keep this in mind as you experiment with different Trigger Advertisement times and intervals in iBeacon configuration.

Also, for motion reports, the driver will automatically revert from 'motion' to 'no motion' device state after 10 seconds.

### TLM Data
Recall this transmits iBeacon device signal strength, battery level, and device temperature.  
The above configuration guidance mentioned to enable TLM data during testing. Be aware that this will fill up your SmartThings device history with a lot of data field updates, since signal strength is constantly changing.  However this may be useful during initial startup and testing.  Device temperature is interesting, but not very useful in most cases.  Remember, this is the **device** temperature, not the ambient temperature.  Battery level is reported by the device in millivolts and the Edge driver converts this to an estimated battery level in terms of percentage for a 2032 type button cell.  Once your testing is complete, it's recommmended to have TLM data normally disabled on the iBeacon device in order to reduce advertisements, preserve battery life, and keep device history focused on the more critical changes in presence, button pushes, and motion.

### Notes about Reliability
I've spent some time closely monitoring the beacons being sent out by these devices so I could tune the grace period to a minimal value, which in turn results in faster 'not present' conditions.  What I've found is that multiple gateways are definitely needed in all but the smallest homes, as the reliability rapidly falls off when more than a couple rooms are between the gateway and beacon device.  I have my beacons advertising every 5 seconds, and the gateway does indeed see this every 5 seconds about 80% of the time if they are reasonably close together.  However there can be periods when no advertisement is received - perhaps due to various household interference from wifi, microwaves, other bluetooth devices, etc. (anything that uses 2.4Ghz).  I've found for me that a grace period of 50 seconds to a minute is necessary to ensure no false not-present conditions occur, which can wreak havoc on automations.  Your mileage will vary!  

All in all, I'm pleased with the reliability and this is definitely more dependable than the moble location presence within SmartThings.
