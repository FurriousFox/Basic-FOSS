# QR code

## QR code algorithm

The main goal of reverse engineering the app was to determine how the entry QR code gets generated.  
*Valid* examples of the output of the QR code when scanned (assuming deviceId `3da383d35b560fbc4749f8e6a28d29cdac3d`):

```text
GM2:V012345678:QVV:1762457893:A8B89BAA
GM2:V012345678:QVV:1762457948:3C15CBB4
GM2:V012345678:BJT:1762466031:52670D24
```

The output is in the format `GM2:{cardnumber}:{guid}:{unix timestamp seconds}:{hash}`  
  
- **GM2**  
    Just a constant, likely for versioning
- **cardnumber**  
    The card number (e.g. "V012345678"),  
    also shown at the [QR code screen in the Basic-Fit app](BasicFitQR-CardNumber.jpeg)
- **[guid](generateShortGUID.md)**  
    3 random characters, based on whether the device is online, either from `0123456789` (offline) or from `ABCDEFGHIJKLMNOPQRSTUVWXYZ` (online) (e.g. "ABC" or "123")
- **unix timestamp seconds**  
    The current [unix timestamp](https://en.wikipedia.org/wiki/Unix_time) in seconds (to verify the QR code isn't too old)
- **hash**  
    The **last 8 characters** of the **sha256** hash of `{cardnumber}{guid}{unix timestamp seconds}{device id}` represented in (uppercase) hex.  
    The **device id** (on android) is 36 random (lowercase) hex characters.  
\
    Example:
  - cardnumber: `V012345678`
  - guid: `QVV`
  - unix timestamp: `1762457893`
  - device id: `3da383d35b560fbc4749f8e6a28d29cdac3d`[^2]  
\
  `SHA256(V012345678QVV17624578933da383d35b560fbc4749f8e6a28d29cdac3d)` = `30AC043045D5BD19252F6696C33796B8C25BADFB20A76F656CB0B15A` **`A8B89BAA`**  
\
  This results in a QR code value of `GM2:V012345678:QVV:1762457893:A8B89BAA`

## Basic-Fit app

A React Native app, compiled using [Hermes](https://github.com/facebook/hermes). The `index.android.bundle` (extracted from the apk) has been decompiled using [hbctool](https://github.com/Kirlif/HBC-Tool), to allow for the reverse engineering of the QR code algorithm itself.

## Optimal reading order

- [firebase.json](firebase.md)
- [getQrCodeConfiguration](getQRCodeConfiguration.md)
- [QrCode](QrCode.md)
- [generateShortGUID](generateShortGUID.md)
- [getQrCode](getQrCode.md)

<sup><sub>AI usage: solely used to help interpret the hasm[^1] syntax</sup></sub>

[^1]: Hermes Assembly
[^2]: the optimal way to extract the deviceId from any Basic-Fit app without Root/Jailbreak is to use the login button and extract it from the url shown in the browser url bar (`https://login.basic-fit.com/?redirect_uri=...&deviceId=3da383d35b560fbc4749f8e6a28d29cdac3d`)
