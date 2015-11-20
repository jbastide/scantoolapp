# scantoolapp

This isn't pretty, and it's still under development.

Here's where we're at:

The custom ScanTool class is under app/lib. It's available everywhere (including the app controller). 

I'm about to integrate paperclip for multiple scan file (trans.dat) upload.

PDF and EAN file parsing are happening. I see that in the console output.

There's no model. Just a custom class, view code, and controller code. The ScanTool class is the 'fat' part of the application.

TODOs:

-Add validations for files.
-Add paperclip integration.
-Make it look like a proper website with styling, etc....
-Re-evaluate RESTful URL names and corresponding controller actions and routes.
-Add persistence layer for results.
-Add results model for interfacing with ActiveRecord.
-Suppress console output and make a styled interface for viewing results.
-Update the match code to give suggested matches.
-Break the ScanTool class out into another module of helper functions. We can then use it with the stand-alone command-line tool. Easier to maintain.
-Consider bringing the command-line scanner tool into this repository, since they're part of the same project.
