IPFS Gateway Redirect Chrome Extension
======================================
Now we can share gateway.ipfs.io urls around and still use IPFS in a distributed
fashion. Plus those not in the know or with a broken build will still have
everything work fine for them. Yay! =)  

Chrome Store: https://chrome.google.com/webstore/detail/gifgeigleclkondjnmijdajabbhmoepo  
Best version: https://github.com/dylanPowers/ipfs-chrome-extension/releases/tag/v0.4.1


What's it do?
-------------
It intercepts requests to `http://gateway.ipfs.io/(ipfs|ipns)/<hash>` on the
fly and redirects them to the ipfs gateway you have running locally. By default this
is localhost:8080 but it can be configured to any server of your choosing. 
It also adds a context menu option and url bar icon that allow you
to easily copy IPFS urls. This fixes urls so that they have the host correctly
set to gateway.ipfs.io rather than localhost:8080. The url bar (aka Omnibox) icon 
requires a simple click to copy the IPFS url, and links require a right click
and where you would normally select "Copy link address" instead select "Copy as IPFS link".

Extra features of the Github release version:
* File access - simply type `/ipfs/QmZSnfkEfjowAAMVJoq2LmZJqdpT4uK6EtrcoWLqkMR4UY`
* HTTPS access - works for resources, like cat pictures, found on 
    [https pages](https://groups.google.com/d/msg/ipfs-users/IKrDkUnIk7E/b2zS2c-KysQJ).
* IPNS domain name redirection - type `ipfs.git.sexy` and get redirected to 
    `/ipns/ipfs.git.sexy`
    
#### About Domain Redirection
This feature is disabled by default as it can have a negative impact on browser
performance in certain instances. Those instances are rare, but they do happen.
Note that with this option enabled, for every domain the browser makes a 
request to, this extension is also making a request to your ipfs daemon to see 
if a request to `/ipns/<domain>` would succeed or fail.

#### Privacy Considerations
Go ahead and read the comments on [issue #5](https://github.com/dylanPowers/ipfs-chrome-extension/issues/5).

Github Release Version
-----------------------
#### Why is this not on the Chrome store?  
The Chrome store is more restrictive when it comes to file URI's and requires 
those permissions to be listed as optional. Unfortunately, due to the issues 
I found in https://github.com/dylanPowers/ipfs-chrome-extension/issues/4 optional 
permissions are impossible to use in this app. Therefore I figured I might as well 
leave that version as it is and have the version listed here be the more powerful 
version.

#### How To Install  
Open up chrome://extensions and drag-n-drop the crx file onto the page. If that 
doesn't work because Chrome is being strange (it's happened to me a few times), 
you can enable developer mode, unzip the zipped version to a safe location and 
click "Load unpacked extension...".  

You will also have to click the checkbox that says "Allow access to file URLs" 
that's present for the extension on the chrome://extensions page.

Building
--------
You can probably see that this is implemented in Dart, and running it requires
the [Dart SDK](https://www.dartlang.org/tools/download.html). 
If you also grab Dartium (Chromium + Dart VM), running it is as simple
as loading the `ext` directory directly into Dartium by opening a tab to 
chrome://extensions and following the instructions
at https://developer.chrome.com/extensions/getstarted#unpacked. 
To run the extension in a standard Chrome browser, you'll have to first compile
it to Javascript. To make a Javascript build simply run:
```sh
pub build ext --mode debug  ## Default mode is production which minifies the JS
```
The build will output to `build/ext` for which you can load it from.
