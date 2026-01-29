# Learning management system app

We want to have:

1. Courses
2. Lesson Modules 
3. Lesson modules sub sections

Per each lesson module sub section we must have a name required and optional description.

Each lesson module su section will have an array of activities, all of them must have:

1. Created at
2. Name (required)
3. Description (optional)

Activities could be:

1. Simple resource file (a lecture, an audio, a video...)

It must be completely integrated to file system and always reference files existing there. Reference the file id not the name nor path.

2. Quiz

It is a different thing, per now we will not write the quiz section, because it is complicated but is coming in the future.
