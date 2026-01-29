# Application bus

I want to create a way to have events released by the apps, for example:

Notes wants to emit an edition over an already existing note, with note id
Notes wants to emit a creation over a new note.

Events must have: event id and some kind of metadata, and we must store the app sender and date, base your implementation of how kafka or rabbit mq works

And to have services (some kind of background tasks) listening those events and doing stuff. 

All events must be stored in the sqlite database to have traces.