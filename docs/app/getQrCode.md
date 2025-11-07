# getQrCode

```js
const hash = crypto.sha256(options.cardNr + options.guid + options.iat + options.deviceId) // concat options and take sha256 hash
                   .toString("hex") // as hex
                   .slice(-8)       // last 8 characters
                   .toUpperCase();  // in uppercase

return `GM2:${options.cardNr}:${options.guid}:${options.iat}:${hash}`;
```
