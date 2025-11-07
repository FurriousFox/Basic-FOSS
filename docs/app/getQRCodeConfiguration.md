# getQRCodeConfiguration

Uses the config stored in Firebase (see "qr_code_configuration" in [firebase.json](src/firebase.json)):

```json
{
    "refreshTime": 5000,
    "useOfflineGuid": true,
    "needsToPreventDoubleScan": true
}
```

and adds all **missing** properties using the following default values

```jsonc
{
    // these properties don't already exist on the config, so will get merged with the firebase config
    "pxSize": 200,               // size of displayed qr codes in pixels
    "pollingTime": 3000,         // how often to poll the "check check-in" endpoint
    "errorCorrectionLevel": "M", // QR ECC level
    "promptVolume": 0.5,         // unknown purposes, accessibility related?
    "locationRefreshTime": 5000, // unknown purposes

    // firebase properties take precedence
    "refreshTime": 10000,             // how often to update the qr code
    "useOfflineGuid": false,          // influences guid character set,
                                      // probably should be assumed true for guaranteed working offline qr code generation
    "needsToPreventDoubleScan": false // unknown purposes
}
```
