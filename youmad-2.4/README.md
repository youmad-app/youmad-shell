Refactoring and cleaning up YouMAD, in order to make it ready for self-hosting in a Docker image.  
The version 2.4 is now much more reliable than the monolithic 2.1.3, especially for album downloads. Download logic, metadata and configuration is a lot more solid. Only limited testing of playlist downloads, downloading playlist has less moving parts, not a lot that *could* break.
