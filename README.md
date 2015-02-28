IPFS Gateway Redirect Chrome Extension
======================================
Now we can share gateway.ipfs.io urls around and still use IPFS in a distributed
fashion. Plus those not in the know or with a broken build will still have
everything work fine for them. Yay! =)  

Chrome Store: https://chrome.google.com/webstore/detail/gifgeigleclkondjnmijdajabbhmoepo

What's it do?
-------------
It intercepts requests to ```http://gateway.ipfs.io/(ipfs|ipns)/<hash>``` on the
fly and redirects them to the ipfs gateway you have running locally on
port 8080. It also adds a context menu option and url bar icon that allow you
to easily copy IPFS urls. This fixes urls so that they have the host correctly
set to gateway.ipfs.io rather than localhost:8080.

#### Things in the works
* Fallback to gateway.ipfs.io when localhost is down
* Ability to configure a custom localhost port or to use a gateway
  somewhere else entirely

Building
--------
You can probably see that this is implemented in Dart. To make a Javascript
build simply run:
```sh
pub build ext --mode debug  ## Default mode is production which minifies the JS
```
The build will output to ```build/ext```. To load the extension into your
browser, follow the instructions at
https://developer.chrome.com/extensions/getstarted#unpacked. So that you're not
constantly compiling to Javascript, I'd recommend loading the extension's Dart
code directly into Dartium which will run the extension natively.
