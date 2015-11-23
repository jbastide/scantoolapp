# scantoolapp

Still under development.

Here's where we're at:

The custom ScanTool class is under app/lib. It's available everywhere (including the app controller). 

Multiple scan files upload (trans.dat) is available via the HTML5 :multiple attribute. Simple.

There's tabular HTML output for the final report. Currently it's in the 'upload' action. This needs to be renamed to something like 'analyze'. 

There's no model. Just a custom class, view code, and controller code. The ScanTool class is the 'fat' part of the application.

TODOs:

-Add validations for files. We can start with server-side validations for now, then move things into the client.
-Deploy to Heroku.
-Configure Twitter Bootstrap and throw in some js. 
-Re-evaluate RESTful URL names and corresponding controller actions and routes.
-Add persistence layer for results.
-Add results model for interfacing with ActiveRecord.
-Update the match code to give suggested matches.
-Break the ScanTool class out into another module of helper functions. We can then use it with the stand-alone command-line tool. Easier to maintain.
-Consider bringing the command-line scanner tool into this repository, since they're part of the same project.
