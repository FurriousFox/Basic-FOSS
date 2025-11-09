# QrCode

```js
const info = fetch("/api/member/info").json()

const guid = generateShortGUID({
    isUsingOfflineGuid,  // QRCodeConfiguration().useOfflineGuid

    online               // reflects current connectivity state
                         // https://docs.expo.dev/versions/latest/sdk/network/#networkstate
});

getQrCode(
    {
        cardNr:   info.member.cardnumber,         // string (e.g. "V012345678")
        guid:     guid                            // string, see generateShortGUID (e.g. "ABC" (online) or "123" (offline))
        iat:      Math.floor(+new Date() / 1000), // current unix timestamp (seconds) as number (e.g. 1762481265)
        deviceId: info.member.deviceId,           // string (e.g. "3da383d35b560fbc4749f8e6a28d29cdac3d")
    }, 
    QRCodeConfiguration().errorCorrectionLevel /* "M" */
);
```
