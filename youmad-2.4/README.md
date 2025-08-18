## What is this?
v. 2.4 is a refactored version of YouMAD?, with more solid and failsafe logic for downloads, metadata and configuration.  
It has config endpoints for Docker, in preparation for a self-hosted version.

## What's with the jump from v.2.1 to 2.4?
The end-goal is a self-hosted Docker image, which will be v.3. There has been a few non-published iterations in between, focusing on refactoring, that weren't presentable enough to publish.

## Project status
Refactoring and cleaning up YouMAD, in order to make it ready for self-hosting in a Docker image.  
The version 2.4 is now much more reliable than the monolithic 2.1.3, especially for album downloads. Download logic, metadata and configuration is a lot more solid. Only limited testing of playlist downloads, downloading playlist has less moving parts, not a lot that *could* break.

## Why no documentation for v.2.4?
v.2.4 has no meaningful feature updates that relates to downloading albums. It's a stop-gap towards self-hosting in Docker. It's stable enough for general use. Unless 2.1.3 breaks, it's a whole lot easier to use that older version.
