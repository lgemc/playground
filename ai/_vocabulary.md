# Vocabulary app

I want to write words pretty difficult to understand, and automatically get their meaning.

I want a vocabulary app to show and search words, sort them by last date entered (descendent), quite simple, almost equal the ui to the notes one, as title the word, and in the details empty blocked and empty at the beginning.

After created a new word, send a message thought the event bus.

Then create a service which uses the autocompletion service to:

1. Edit this vocabulary entry with: meaning, some samples, 5, but create
a configuration with the amount of sample phrases, local for the vocabulary app.

Create:

1. A configuration to move to a new queue new vocabulary added from bus, the new queue system must be used. 
2. Vocabulary app which can: add words, edit them, and delete them.
3. When editing or creating vocabulary, he message must be sent to the app bus, queue service must move those messages to the new queue and the service that defines the word and give examples must add this information. Only if word has changed, not if content has changed (it must be also editable).

Define by your self the events released in vocabulary app and queue names.
Those must be snack case and have verbs in infinitive.

