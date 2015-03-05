IPFS Gateway Redirect Chrome Extension
======================================
Now we can share gateway.ipfs.io urls around and still use IPFS in a distributed
fashion. Plus those not in the know or with a broken build will still have
everything work fine for them. Yay! =)  

Chrome Store: https://chrome.google.com/webstore/detail/gifgeigleclkondjnmijdajabbhmoepo

What's it do?
-------------
It intercepts requests to ```http://gateway.ipfs.io/(ipfs|ipns)/<hash>``` on the
fly and redirects them to the ipfs gateway you have running locally. By default this
is localhost:8080 but it can be configured to any server of your choosing. 
It also adds a context menu option and url bar icon that allow you
to easily copy IPFS urls. This fixes urls so that they have the host correctly
set to gateway.ipfs.io rather than localhost:8080. The url bar (aka Omnibox) icon 
requires a simple click to copy the IFPS url, and links require a right click
and where you would normally select "Copy link address" instead select "Copy as IPFS link".

#### Things in the works
* [Fallback to gateway.ipfs.io when the local gateway is down](https://github.com/dylanPowers/ipfs-chrome-extension/issues/2)

Building
--------
You can probably see that this is implemented in Dart, and running it requires
the [Dart SDK](https://www.dartlang.org/tools/download.html). 
If you also grab Dartium (Chromium + Dart VM), running it is as simple
as loading the ```ext``` directory directly into Dartium by opening a tab to 
chrome://extensions and following the instructions
at https://developer.chrome.com/extensions/getstarted#unpacked. 
To run the extension in a standard Chrome browser, you'll have to first compile
it to Javascript. To make a Javascript build simply run:
```sh
pub build ext --mode debug  ## Default mode is production which minifies the JS
```
The build will output to ```build/ext``` for which you can load it from.
