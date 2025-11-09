# generateShortGUID

Takes 3 random characters from a character set determined by "isUsingOfflineGuid" and "online" (passed by [QrCode](QrCode.md))

```js
if (!isUsingOfflineGuid) charSet = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ'

else if (online)         charSet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
else                     charSet = '0123456789'

// take 3 random characters, allows for duplicates
return charSet[Math.floor(Math.random() * charSet.length)]
     + charSet[Math.floor(Math.random() * charSet.length)]
     + charSet[Math.floor(Math.random() * charSet.length)];
```

**isUsingOfflineGuid** is true by default (see firebase.json)  
**online** reflects current connectivity state
