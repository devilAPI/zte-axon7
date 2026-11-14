# Open radio HAL (RIL) for the Axon 7 on LineageOS 24: research and plan

Status 2026-11-14. Research only, nothing built or run on the phone.
Marks: **[V]** read in the source named, **[K]** from memory of libqmi's QMI
definitions (not in the reference trees; confirm with `qmicli -v` on Nura
before coding), **[A]** assumption.

Starting point: modem online over QRTR, QMI framing over `AF_QIPCRTR` works
(`device/zte/axon7m/qcom/modem-online`, `gnss/LocClient.cpp`). No mobile data
(IPA v2.5) and no call audio (q6voice) in the kernel.

## Summary

- **qrild is a reference, not a base.** It does not build (it needs the old
  libqril API that the standalone libqril no longer has), targets radio AIDL
  V1, has no SMS and no voice, and its author calls it a hacky proof of
  concept.
- **AOSP 17 has two AIDL radio HALs to start from**, both found in the tree:
  `libminradio` (base classes that answer every method of five radio
  interfaces) and the emulator's `ranchu` HAL (complete, AT commands).
- **Recommended:** a new C++ service `android.hardware.radio-service.axon7m`
  on `libminradio`, with a shared QMI client grown out of `LocClient`, plus
  an own `IRadioMessaging`. No `IRadioVoice` until q6voice exists.
- **First milestone** (SIM, operator and signal, SMS): about 3-4 weeks of
  focused work. The largest single piece is SIM file access, which the
  framework needs before it accepts a SIM as loaded.
- **Decision needed:** `libminradio` is built against radio V4, the device's
  target FCM level 202404 allows only V3. Raising `manifest.xml` to 202504
  is the simple route (section 2.2).

## 1. qrild and libqril

Source: `/srv/los24/ref/aospm-qrild`, `/srv/los24/ref/aospm-libqril` [V].

| | qrild | libqril |
|---|---|---|
| Language | C++ (8 files, 3,300 lines) | C, small C++ wrapper (about 3,000 lines without `timespec.c`) |
| Interface | **AIDL** split radio HAL, `android.hardware.radio.*-V1-ndk`, binary `android.hardware.radio-service`. Not libril, not HIDL | none; QMI/QRTR client library (service discovery, async messages, events) |
| Last commit | 2022-10-06 (README: "development is currently halted"). The clone has one commit | 2022-10-06 |
| License | Apache-2.0 headers (Linaro) in the `.cc` files; no LICENSE file | Apache-2.0 headers in most `.c` files; `.qmi` files, `lib/*.h` have none; `timespec.c` public domain |

Completeness of qrild, counted from the QMI calls in each file [V]:

| Area | State |
|---|---|
| Config | `getSimSlotsStatus` via UIM Get Slot Status |
| Modem | operating mode (DMS), IMEI, baseband version |
| SIM | card status, slot status, file attributes, read transparent/record, open logical channel; IMSI marked "FIXME" (taken from DMS Get MSISDN); no PIN |
| Network | serving system, signal strength, operator/PLMN name, cell location, LTE CA info, automatic registration |
| Data | WDS start network interface, mux port binding, DPM open port; README: data call came up, Android never configured DNS |
| **SMS** | **stubs only**, no QMI call in `qrild_android_messaging.cc`, no WMS definitions in libqril |
| **Voice** | **stubs only**, no VOICE definitions |

Can it be built for Android 17 as is: **no**.

1. qrild includes `qrild_qmi.h`, `qrild_link.h`, `qrild.h`, `qrild_msg.h` and
   calls `qrild_qmi_*()`: the old in-tree libqril. The standalone libqril only
   keeps part of it in `old/`. Its `Android.bp` lists `qrild_link.cc` (now in
   `old/`) and generated `qmi/qmi_*.c` files that need AOSPM's forks of
   `qmic` and `qrtr`, which are not in the reference trees [V].
2. Radio AIDL V1 against a framework built on V5; the FCM matrices from 202404
   on accept V3 at the lowest (section 2.2). V1 to V4 adds methods in every
   interface (network: 36 implemented in qrild, 55 in the current interface).
3. Its `.rc` runs the HAL under `logwrapper`; requests are synchronous QMI
   calls on binder threads; the README names memory leaks.

Changes needed would be a rewrite of the QMI layer plus an interface port,
which is more work than using its mapping code as a reference. Worth taking
from it: the `.qmi` definitions (UIM, NAS, DMS, WDS, WDA, DPM), the card
status to `CardStatus` mapping in `qrild_android_sim.cc`, the registration
state mapping in `qrild_android_network.cc`, and `notes/` (qmicli traces).

## 2. What Android 17 needs

### 2.1 Interfaces and how the framework finds them

`frameworks/opt/telephony/.../RIL.java` [V]:

- A service counts as supported when `ServiceManager.isDeclared(
  "<descriptor>/slot1")` is true (`isRadioServiceSupported`). If any of
  data, messaging, modem, network, sim, voice, ims is declared, the HAL is
  treated as AIDL ("2.0"), and HIDL is not tried.
- Undeclared services get `RADIO_HAL_VERSION_UNSUPPORTED`; requests to them
  complete with an error in the framework (`canMakeRequest`), no crash.
- Feature flags map to services: `telephony.calling` to voice,
  `telephony.messaging` to messaging, `telephony.data` to data,
  `telephony.ims` to ims. A mismatch is only logged (`validateFeatureFlags`).
- Proxies are fetched with `ServiceManager.waitForDeclaredService`. **A HAL
  that is declared in VINTF but not running blocks that call.** Declare only
  what the service really registers, and start the service independent of
  the modem's state.
- `IRadioConfig/default` is fetched the same way by `RadioConfig.java`.

Minimum set for a device with telephony: **IRadioConfig, IRadioModem,
IRadioSim, IRadioNetwork**, plus IRadioData (every tested AOSP configuration
has it) and, for SMS, IRadioMessaging. AOSP's own minimal HAL ships exactly
config, data, modem, network, sim [V: `minradio-example.xml`]. IRadioVoice,
IRadioIms, ISap are optional.

Interface sizes in this tree (methods) [V]: config 12, modem 18, sim 37,
network 55, data 19, messaging 23 (8 of them CDMA, deprecated), voice 39.

### 2.2 Versions

- Frozen versions in the tree: 1-5 for config, data, messaging, modem,
  network, sim, voice. The framework links V5 [V: `frameworks/opt/telephony/Android.bp`].
- Compatibility matrices [V]: level 202404 accepts **3**, 202504 **3-4**,
  202604 **3-5**.
- The device's `manifest.xml` has `target-level="202404"`. `libminradio` is
  built against **V4**. Options: raise the target level to 202504 (check the
  other HALs of the device against that matrix, as was done for GNSS V4), or
  copy `libminradio` into the device tree and build it against V3 (methods
  added in V4 lose their `override`, some editing).

### 2.3 What must answer so the phone process stays healthy

Rules that the AOSP implementations follow [V in `libminradio`]:

1. **Every request gets a response**, at least `REQUEST_NOT_SUPPORTED`. A
   request without a response holds a wakelock for 60 s
   (`DEFAULT_WAKE_LOCK_TIMEOUT_MS`) and feeds the radio bug detector.
2. Binder calls return OK; errors travel in `RadioResponseInfo.error`. (The
   GNSS HAL's run 33 crash came from the same class of mistake.)
3. After `setResponseFunctions` on IRadioModem: `rilConnected`, then
   `radioStateChanged` [V: `RadioModem.cpp` lines 214-215].
4. Indications before `setResponseFunctions` must not crash the HAL
   (`GuaranteedCallback` substitutes a default callback).

Requests the framework sends at start and expects real answers to [A, from
the set that `libminradio` and the example implement with data]:

| Interface | Methods |
|---|---|
| Config | `getHalDeviceCapabilities`, `getPhoneCapability`, `getSimSlotsStatus`, `getSimultaneousCallingSupport` |
| Modem | `setRadioPower`, `getBasebandVersion`, `getImei`, `getDeviceIdentity`, `getRadioCapability`, `getHardwareConfig`, `getModemStackStatus`, `sendDeviceState`, `setIndicationFilter` |
| SIM | `getIccCardStatus`, `getImsiForApp`, `iccIoForApp` (ICCID, AD, SPN, MSISDN, UST, MWIS, SMSP and more), `areUiccApplicationsEnabled`, `getFacilityLockForApp`, `iccOpenLogicalChannel` (carrier privileges; an error answer is fine), `supplyIccPinForApp` for a PIN-locked SIM |
| Network | `getVoiceRegistrationState`, `getDataRegistrationState`, `getOperator`, `getNetworkSelectionMode`, `getSignalStrength`, `get/setAllowedNetworkTypesBitmap`, `setSignalStrengthReportingCriteria`, `setCellInfoListRate`, `getCellInfoList` |
| Data | `getDataCallList` (empty), `setDataAllowed`, `setInitialAttachApn`, `setDataProfile`; `setupDataCall` fails until IPA exists |
| Messaging | `sendSms`, `acknowledgeLastIncomingGsmSms`, `getSmscAddress`, `reportSmsMemoryStatus`, `setGsmBroadcastConfig/Activation` |

### 2.4 Wi-Fi-only device versus this device today

- No `IRadio*` declared: RIL falls back to the HIDL lookup, finds nothing,
  marks the services disabled. `mIsCellularSupported` comes from
  `isVoiceCapable() || isSmsCapable() || isDataCapable()`; with a vendor API
  level below 2024Q2 these read `config_voice_capable`, `config_sms_capable`,
  `config_mobile_data_capable`, all **true** by default, so the framework
  still believes there is a cellular radio [V: `TelephonyManager.hasCapability`,
  `core/res/res/values/config.xml`]. A clean Wi-Fi-only build overlays the
  three to false.
- `ro.radio.noril=yes` (device.mk): no reader found in
  `frameworks/opt/telephony`, `packages/services/Telephony`,
  `frameworks/base` (core, services/java, telephony), `hardware/ril`,
  `system/core` (init, rootdir). It appears to do nothing on Android 17.
- `lineage_axon7m.mk` inherits `full_base_telephony.mk`, which pulls
  `telephony_vendor.mk` and with it **`rild`** (legacy libril, HIDL radio
  1.0/1.1, AT reference-ril). `rild.rc` starts it unconditionally, and the
  framework accepts HIDL only from 1.4. Check on the phone:
  `getprop init.svc.vendor.ril-daemon`. The new HAL should not ship next to it.

### 2.5 Reference implementations in the tree

| Path | What | Modem link | Use |
|---|---|---|---|
| `hardware/interfaces/radio/aidl/minradio/libminradio` (2024-2025, Apache-2.0) | Base classes for config, data, modem, network, sim on **V4**; every method has a default (`notSupported` or a sane value); response tracking, SIM file system helpers. Comment in `service.cpp`: "Non-virtual implementation would set up and initialize connection to the modem here" | none (virtual) | **base of the new HAL** |
| `.../minradio/minradio-example` | 5 small subclasses, about 500 lines, fixed data | none | template for the service and VINTF fragment |
| `device/generic/goldfish/hals/radio` (`android.hardware.radio-service.ranchu`, also Cuttlefish's `com.google.cf.rild`) | **Complete** AIDL V5 HAL: config, data, ims, messaging, modem, network, sim, voice, sap; 11,000 lines | AT commands over `AF_VSOCK` to the emulator / `modem_simulator` (`AtChannel.cpp`, `main.cpp`) | reference for what each method should return (SMS PDUs, `iccIoForApp`, call states). Swapping its AT layer for QMI means rewriting most of each file, since AT parsing is inline |
| `hardware/interfaces/radio/aidl/compat` | AIDL front for a HIDL 1.x vendor RIL | HIDL | struct conversions only |
| `hardware/ril` (libril, reference-ril, rild) | legacy HIDL 1.0/1.1 | AT | none |

## 3. Recommended path

### 3.1 Design

New module `device/zte/axon7m/radio/`, binary
`android.hardware.radio-service.axon7m`, Apache-2.0:

- **QMI layer:** lift the socket code of `gnss/LocClient.cpp` into a shared
  `QmiClient` (name service lookup with NEW_SERVER/DEL_SERVER, one reader
  thread, transaction matching with timeouts, indication callbacks,
  re-lookup after a modem restart). One instance per QMI service. Message
  structs written by hand as in the GNSS HAL, checked against the `.qmi`
  files in libqril.
- **HAL layer:** subclasses of `libminradio` for config, modem, sim,
  network, data; own `RadioMessaging` on `BnRadioMessaging` (V4) with the
  same response helpers. QMI responses complete the AIDL response from the
  reader thread; binder threads never wait on the modem.
- **Modem power:** the HAL takes over DMS Set Operating Mode in
  `setRadioPower` (online 0, low power 1 for airplane mode) and re-applies it
  after a modem restart; `axon7m-modem-online` is retired at that point (GNSS
  depends on the modem being online, so not before).
- **SELinux:** label the binary `hal_radio_default_exec` (the domain and its
  `hal_telephony` server attributes exist in `system/sepolicy/vendor`); add
  `allow hal_radio_default self:qipcrtr_socket create_socket_perms_no_ioctl;`
  as for `hal_gnss_default`.
- **init:** `class hal`, `user radio`, `group radio inet misc log readproc
  wakelock` (as ranchu's `.rc`).
- **Product:** drop `rild`; add the feature files for telephony base,
  subscription, radio access, messaging; not calling and not data until they
  work. Overlay `config_voice_capable=false` until voice exists.

### 3.2 Steps, QMI messages, effort

Effort in days of focused work, including test rounds on the phone.

**Step 0: probe the modem by hand (0.5 d).** Section 4, extended to DMS Get
IDs, NAS Get Serving System, NAS Get Signal Info. Shows the SIM is seen and
the modem registers without any HAL.

**Step 1: skeleton (2-3 d).** Service on `libminradio`, QmiClient, VINTF
fragment, sepolicy, features. Result: framework binds all declared services,
radio state ON, "no SIM", no crash loop, no wakelock timeouts in
`logcat -b radio`.

| QMI | Message | Id | TLVs |
|---|---|---|---|
| DMS 2 | Get Operating Mode | 0x002D [V] | resp 0x01 u8 mode |
| DMS 2 | Set Operating Mode | 0x002E [V] | req 0x01 u8 mode |
| DMS 2 | Get IDs | 0x0025 [V] | resp 0x11 IMEI string, 0x13 IMEI software version |
| DMS 2 | Get Revision | 0x0023 [V] | resp 0x01 string |
| DMS 2 | Set Event Report | 0x0001 [K] | req 0x14 u8 operating mode reports; indication 0x0001 |

**Step 2: SIM detected and loaded (4-6 d).**

| QMI | Message | Id | TLVs |
|---|---|---|---|
| UIM 11 | Get Card Status | 0x002F [V] | resp 0x10 card status (layout in section 4) |
| UIM 11 | Event Registration | 0x002E [K] | req 0x01 u32 mask, bit 0 card status |
| UIM 11 | Status Change indication | 0x0032 [K] | 0x10 card status |
| UIM 11 | Read Transparent | 0x0020 [V] | req 0x01 session {u8 type, u8 aid len, aid}, 0x02 file {u16 id, u8 path len, path}, 0x03 {u16 offset, u16 length}; resp 0x10 {sw1, sw2}, 0x11 {u16 len, data} |
| UIM 11 | Read Record | 0x0021 [V] | as above, 0x03 {u16 record, u16 length} |
| UIM 11 | Get File Attributes | 0x0024 [V] | resp 0x11 attributes incl. raw FCP data |
| UIM 11 | Verify PIN | 0x0026 [K] | req 0x01 session, 0x02 {u8 pin id, u8 len, pin}; resp 0x10 retries |
| UIM 11 | Unblock PIN / Change PIN / Set PIN Protection | 0x0027 / 0x0028 / 0x0025 [K] | |
| UIM 11 | Open Logical Channel | 0x0042 [V] | req 0x01 slot, 0x10 AID; resp 0x10 channel |
| UIM 11 | Refresh indication | 0x0033 [V] | 0x10 event |
| UIM 11 | Get Slot Status | 0x0047 [V] | may be unknown to this 2016 firmware; qrild depends on it, the new HAL must not |
| DMS 2 | UIM Get IMSI | 0x0043 [V] | resp 0x01 string; or read EF 6F07 |

Mapping: `getIccCardStatus` from the card status TLV; `iccIoForApp` commands
176 (READ BINARY), 178 (READ RECORD), 192 (GET RESPONSE) to the three UIM
file messages (trace of the last one in `aospm-qrild/notes/dev-notes.md`);
`getSimSlotsStatus` from the same card status. Session type 0 is "primary GW
provisioning" [V]. Test first with a SIM whose PIN is off.

**Step 3: operator and signal (4-6 d).**

| QMI | Message | Id | TLVs |
|---|---|---|---|
| NAS 3 | Register Indications | 0x0003 [V] | req 0x13 serving system, 0x17 network time, 0x18 system info, 0x19 signal info (u8 each) |
| NAS 3 | Get Serving System, indication | 0x0024 [V] | 0x01 {u8 registration (0 no, 1 yes, 2 searching, 3 denied), u8 cs attach, u8 ps attach, u8 network, u8 n, radio interfaces (4 GSM, 5 UMTS, 8 LTE)}, 0x12 {u16 mcc, u16 mnc, name}, 0x1D lac, 0x1E cell id |
| NAS 3 | Get System Info, indication | 0x004D, 0x004E [K] | per-technology service status, PLMN, TAC, cell id; preferable to Serving System on LTE |
| NAS 3 | Get Signal Info, indication | 0x004F, 0x0051 [V] | 0x12 GSM i8 rssi; 0x13 WCDMA {i8 rssi, i16 ecio}; 0x14 LTE {i8 rssi, i8 rsrq, i16 rsrp, i16 snr} |
| NAS 3 | Config Signal Info | 0x0050 [K] | report thresholds |
| NAS 3 | Get Operator Name, indication | 0x0039, 0x003A [V] | 0x10 SPN, 0x13 operator string, 0x14 NITZ names |
| NAS 3 | Get PLMN Name | 0x0044 [V] | req 0x01 {u16 mcc, u16 mnc} |
| NAS 3 | Get/Set System Selection Preference | 0x0034, 0x0033 [V] | 0x11 mode preference [K], 0x16 network selection |
| NAS 3 | Initiate Network Register | 0x0022 [V] | req 0x01 u8 action (1 automatic, 2 manual) |
| NAS 3 | Get Cell Location Info | 0x0043 [V] | 0x13 LTE intra-frequency |
| NAS 3 | Network Time indication | 0x004C [K] | NITZ for `nitzTimeReceived` |

Mapping: `getVoiceRegistrationState`/`getDataRegistrationState` with
`CellIdentity`, `getOperator`, `getSignalStrength` plus
`currentSignalStrength`, `networkStateChanged`, `getNetworkSelectionMode`,
allowed network types from the mode preference.

**Step 4: SMS (3-5 d).** All ids [K]: libqril has no WMS definitions.

| QMI | Message | Id | TLVs |
|---|---|---|---|
| WMS 5 | Set Event Report | 0x0001 | req 0x10 u8 report new MT messages |
| WMS 5 | Event Report indication | 0x0001 | 0x11 transfer-route message {u8 ack required, u32 transaction id, u8 format, u16 len, PDU}; 0x10 {u8 storage, u32 index} for stored messages |
| WMS 5 | Set Routes | 0x0032 | route all classes "transfer only" so nothing is stored on SIM or in the EFS |
| WMS 5 | Raw Send | 0x0020 | req 0x01 {u8 format (6 = 3GPP point-to-point), u16 len, PDU with SMSC prefix}; resp 0x01 u16 message reference, 0x12 {u16 rp cause, u8 tp cause} |
| WMS 5 | Send Ack | 0x0037 | req 0x01 {u32 transaction id, u8 protocol (1 = 3GPP), u8 success} |
| WMS 5 | Get / Set SMSC Address | 0x0034, 0x0035 | resp 0x01 {char type[3], u8 len, digits} |
| WMS 5 | Raw Read, Delete, List Messages | 0x0022, 0x0024, 0x0031 | only if SIM storage is wanted |

Mapping: `sendSms` (the AIDL `smscPdu` + `pdu` hex strings, as in ranchu's
`RadioMessaging.cpp`), `newSms` indication, `acknowledgeLastIncomingGsmSms`,
`newSmsStatusReport`, `getSmscAddress`.

**Hardening (3-5 d).** Modem restart during early boot (Nura's `axon7-modem`
documents several restarts in the first two minutes), airplane mode, SIM
removal, PIN entry, `logcat -b radio` free of timeouts over a day.

**Total to the first milestone: 16-25 days**, in line with PLAN.md's 6-10
weeks for the whole modem control row.

**Later.** Voice: IRadioVoice on QMI VOICE 9 (Dial Call 0x0020, End Call
0x0021, Answer Call 0x0022, All Call Status indication 0x002E, Get All Call
Info 0x002F, all [K]), 2-3 weeks plus q6voice in the kernel and the audio
HAL's voice path. Data: IPA v2.5 port, then WDS Start Network Interface 0x0020,
Get Current Settings 0x002D, Bind Mux Data Port 0x00A2, WDA Set Data Format
0x0020, DPM Open Port 0x0020 [V in libqril], rmnet setup over netlink
(`aospm-qrild/notes/netlink.md`).

### 3.3 Risks

| Risk | Effect | Handling |
|---|---|---|
| `com.android.phone` blocked or looping | HAL declared but not registered: `waitForDeclaredService` blocks; HAL crash: death recipient, re-bind, repeated start-up requests | register all declared instances before joining the thread pool; service start independent of the modem; first tests with the `.rc` `disabled` and a manual `start` |
| Unanswered requests | 60 s wakelocks, radio bug detector | `libminradio` defaults; a QMI timeout answers with `MODEM_ERR` |
| VINTF level | V4 HAL rejected at target level 202404 | section 2.2 |
| SELinux | `qipcrtr_socket` denied in `hal_radio_default`; `adb shell` tests as root hide this | rule in 3.1; test from init, not only from the shell |
| SIM not powered or not read | card state "error" (for example no ATR) | step 0 shows it; the SIM supplies are modem-controlled [A] |
| SIM loading stalls | framework reads 20-30 elementary files; one wrong status word keeps the SIM in "not ready" | compare `iccIoForApp` answers with ranchu and with qmicli traces on Nura |
| SMS on LTE without IMS | needs SMS over SGs (combined attach); carriers without 2G/3G fallback may require IMS | check registration in step 0 (`cs attach` in Serving System); IMS is out of scope |
| Read-only rmtfs | the modem cannot store settings or messages in the EFS | "transfer only" SMS routes; set preferences at every start |
| Second SIM slot | card status lists two slots | single-SIM HAL (slot1) first |
| Unverified ids | WMS, VOICE and some UIM/NAS ids are [K] | qmicli `-v` traces on Nura before each step |
| Suspend | indications must wake the phone | later; suspend is broken on msm8996 mainline anyway |

## 4. First experiment: SIM state over QMI UIM

Request: UIM (service 11) **Get Card Status, message 0x002F, no TLVs** [V].
On QRTR the QMI message is `00 | txn u16 | msg u16 | len u16 | TLVs`, as in
`axon7m-modem-online.c`. Response TLVs: 0x02 result {u16 result, u16 error},
0x10 card status:

```
u16 index_gw_primary      (high byte slot, low byte app; 0xFFFF none)
u16 index_1x_primary, u16 index_gw_secondary, u16 index_1x_secondary
u8  number of cards (slots)
per card:
  u8 card_state           0 absent, 1 present, 2 error
  u8 upin_state, u8 upin_retries, u8 upuk_retries
  u8 error_code           with card_state 2 (3 = no ATR received)
  u8 number of apps
  per app:
    u8 type               1 SIM, 2 USIM, 3 RUIM, 4 CSIM, 5 ISIM
    u8 state              1 detected, 2 PIN1 required, 3 PUK1 required,
                          4 check personalization, 5 PIN1 blocked,
                          6 illegal, 7 ready
    u8 personalization_state, feature, retries, unblock_retries
    u8 aid_len, aid[aid_len]
    u8 upin_replaces_pin1
    u8 pin1_state         1 enabled not verified, 2 verified, 3 disabled
    u8 pin1_retries, puk1_retries, pin2_state, pin2_retries, puk2_retries
```

Layout from `aospm-libqril/qmi/qril_uim.qmi`; checked against the qmicli
trace in `aospm-qrild/notes/uim_get_card_status.txt` (OnePlus 6: slot 1
present, USIM ready, PIN1 disabled; slot 2 error 3).

**On Nura (no build):** `qmicli -d qrtr://0 --uim-get-card-status`, add `-v`
for the raw bytes.

**On LineageOS 24:** there is no generic QMI tool on the phone, so a small
one is needed. Source below (148 lines, built on the socket code of
`axon7m-modem-online.c`; compiled with host gcc and its decoder run against
the trace above, not run on the phone). Build it static with the NDK like
the modem tool, then:

```
adb root
adb push qmi-raw /data/local/tmp/
adb shell /data/local/tmp/qmi-raw 11 0x2f     # SIM
adb shell /data/local/tmp/qmi-raw 2 0x25      # IMEI in TLV 0x11
adb shell /data/local/tmp/qmi-raw 3 0x24      # serving system (registration, PLMN)
adb shell /data/local/tmp/qmi-raw 3 0x4f      # signal: TLV 0x14 = LTE rssi, rsrq, rsrp, snr
```

Expected for an inserted, unlocked SIM: `slot 1: card present, 1 app(s)`
(or more) and `USIM, ready`. `card absent` on every slot: no SIM seen.
`PIN1 required`: SIM seen, locked. `result 1, QMI error N`: the modem
refused the request (the HAL must map these).

```c
/*
 * qmi-raw: one QMI request over QRTR, response as hex; decodes UIM
 * GET_CARD_STATUS. Usage: qmi-raw SERVICE MSGID [TLV bytes in hex]
 * SPDX-License-Identifier: Apache-2.0
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>
#include <linux/qrtr.h>

#ifndef AF_QIPCRTR
#define AF_QIPCRTR 42
#endif

static int lookup(unsigned service, struct sockaddr_qrtr *out)
{
	struct sockaddr_qrtr local, ctl = { 0 };
	struct qrtr_ctrl_pkt pkt = { 0 };
	socklen_t sl = sizeof(local);
	struct timeval tv = { 2, 0 };
	int fd = socket(AF_QIPCRTR, SOCK_DGRAM, 0), found = 0;

	if (fd < 0 || getsockname(fd, (struct sockaddr *)&local, &sl) < 0)
		return -1;
	setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
	pkt.cmd = QRTR_TYPE_NEW_LOOKUP;
	pkt.server.service = service;
	ctl.sq_family = AF_QIPCRTR;
	ctl.sq_node = local.sq_node;
	ctl.sq_port = QRTR_PORT_CTRL;
	if (sendto(fd, &pkt, sizeof(pkt), 0, (struct sockaddr *)&ctl, sizeof(ctl)) < 0)
		return -1;
	/* the list ends with an empty NEW_SERVER */
	while (recv(fd, &pkt, sizeof(pkt), 0) >= (ssize_t)sizeof(pkt)) {
		if (pkt.cmd != QRTR_TYPE_NEW_SERVER || !pkt.server.service)
			break;
		if (pkt.server.service == service && !found) {
			out->sq_family = AF_QIPCRTR;
			out->sq_node = pkt.server.node;
			out->sq_port = pkt.server.port;
			found = 1;
		}
	}
	close(fd);
	return found ? 0 : -1;
}

static void card_status(const uint8_t *v, int len)
{
	static const char *cs[] = { "absent", "present", "error" };
	static const char *as[] = { "unknown", "detected", "PIN1 required", "PUK1 required",
				    "check personalization", "PIN1 blocked", "illegal", "ready" };
	static const char *at[] = { "unknown", "SIM", "USIM", "RUIM", "CSIM", "ISIM" };
	int i = 8, cards, c, a;

	if (len < 9)
		return;
	printf("primary GW app: slot %u app %u (0xffff: none)\n", v[1], v[0]);
	cards = v[i++];
	for (c = 0; c < cards && i + 6 <= len; c++) {
		int apps = v[i + 5];

		printf("slot %d: card %s", c + 1, v[i] < 3 ? cs[v[i]] : "?");
		if (v[i] == 2)
			printf(" (error code %u)", v[i + 4]);
		printf(", %d app(s)\n", apps);
		i += 6;
		for (a = 0; a < apps && i + 7 <= len; a++) {
			int aidlen = v[i + 6], p = i + 7 + aidlen;

			if (p + 7 > len)
				return;
			printf("  app %d: %s, %s, PIN1 state %u (0 unknown, 1 enabled not verified, "
			       "2 verified, 3 disabled, 4 blocked, 5 permanently blocked), "
			       "%u PIN / %u PUK tries left\n", a, v[i] < 6 ? at[v[i]] : "?",
			       v[i + 1] < 8 ? as[v[i + 1]] : "?", v[p + 1], v[p + 2], v[p + 3]);
			i = p + 7;
		}
	}
}

int main(int argc, char **argv)
{
	struct sockaddr_qrtr svc = { 0 };
	struct timeval tv = { 5, 0 };
	uint8_t req[512], buf[4096];
	unsigned service, msg;
	int fd, tlvlen = 0, i, len;
	ssize_t n;

	if (argc < 3) {
		fprintf(stderr, "usage: %s SERVICE MSGID [TLV hex bytes]\n", argv[0]);
		return 2;
	}
	service = strtoul(argv[1], NULL, 0);
	msg = strtoul(argv[2], NULL, 0);
	for (i = 3; i < argc && tlvlen < (int)sizeof(req) - 7; i++)
		req[7 + tlvlen++] = strtoul(argv[i], NULL, 16);
	if (lookup(service, &svc)) {
		fprintf(stderr, "service %u not found on QRTR (modem up?)\n", service);
		return 1;
	}
	printf("service %u at %u:%u\n", service, svc.sq_node, svc.sq_port);
	fd = socket(AF_QIPCRTR, SOCK_DGRAM, 0);
	setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
	req[0] = 0;				/* 0 request, 2 response, 4 indication */
	req[1] = 1; req[2] = 0;			/* transaction id */
	req[3] = msg & 0xff; req[4] = msg >> 8;
	req[5] = tlvlen & 0xff; req[6] = tlvlen >> 8;
	if (sendto(fd, req, 7 + tlvlen, 0, (struct sockaddr *)&svc, sizeof(svc)) < 0) {
		perror("sendto");
		return 1;
	}
	do {
		n = recv(fd, buf, sizeof(buf), 0);
		if (n < 7) {
			fprintf(stderr, "no response\n");
			return 1;
		}
	} while (buf[0] != 2 || (unsigned)(buf[3] | buf[4] << 8) != msg);
	len = buf[5] | buf[6] << 8;
	if (len > n - 7)
		len = n - 7;
	for (i = 7; i + 3 <= 7 + len; ) {
		int t = buf[i], l = buf[i + 1] | buf[i + 2] << 8, k;

		if (i + 3 + l > 7 + len)
			break;
		printf("TLV 0x%02x len %d:", t, l);
		for (k = 0; k < l; k++)
			printf(" %02x", buf[i + 3 + k]);
		printf("\n");
		if (t == 0x02 && l >= 4)
			printf("result %u, QMI error %u\n", buf[i + 3] | buf[i + 4] << 8,
			       buf[i + 5] | buf[i + 6] << 8);
		if (service == 11 && msg == 0x2f && t == 0x10)
			card_status(buf + i + 3, l);
		i += 3 + l;
	}
	return 0;
}
```

## Sources

- `/srv/los24/ref/aospm-qrild` (README, `Android.bp`, `qrild/*.cc`, `notes/`), `/srv/los24/ref/aospm-libqril` (`qmi/*.qmi`, `lib/libqril_qmi.h`, `Android.bp`)
- `/srv/los24/lineage-24.0/hardware/interfaces/radio/aidl` (`Android.bp`, `android/hardware/radio/*`, `minradio/`, `compat/`)
- `/srv/los24/lineage-24.0/hardware/interfaces/compatibility_matrices/compatibility_matrix.{202404,202504,202604}.xml`
- `/srv/los24/lineage-24.0/frameworks/opt/telephony/src/java/com/android/internal/telephony/RIL.java`, `frameworks/base/telephony/java/android/telephony/TelephonyManager.java`
- `/srv/los24/lineage-24.0/device/generic/goldfish/hals/radio`, `device/google/cuttlefish/apex/com.google.cf.rild`, `hardware/ril`
- `/srv/los24/lineage-24.0/system/sepolicy/vendor/hal_radio_default.te`, `private/hal_telephony.te`
- `/srv/los24/lineage-24.0/build/make/target/product/{full_base_telephony,telephony_vendor}.mk`
- This repo: `device/zte/axon7m/{qcom,gnss,device.mk,manifest.xml}`, Nura's `axon7-modem`
