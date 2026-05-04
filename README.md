# dossier.el
Experimental pdf viewing/notetaking interface for Emacs/Org-Mode

## !!! Warning !!!

This project was largely written by an LLM to specifications based on my particular setup. I'm providing it here for illustrative purposes; it may be unsuitable for your system or incompatible with your Emacs setup. Although you are welcome to copy whatever seems useful to you, please read the code carefully if you decide to use any of it.

## Dossier

<img width="1914" height="1047" alt="{A4CE1E1E-D256-406B-BF3A-325014551749}" src="https://github.com/user-attachments/assets/e77f6ba1-59ec-4ca9-9160-a6dc73a3026e" />

### TLDR

I asked an LLM to help me implement a minor mode for Emacs which would smooth out my workflow when viewing and taking notes on a large amount of small PDF files (the example above shows the recently declassified JFK Assassination Records). I intended it to be largely an educational experience in Elisp, and it was that, but what it gave me has proved to be genuinely useful (*and fancy*), so I decided to share it here, in case it could benefit anyone else.

The prompt I used to start the process (which was a long, iterative dialogue) is copied below, but these are the basic features:

- **Automatic three-window layout**: a narrow Dired index of the PDF directory on the left, the main viewing window in the middle, and an Org-mode buffer on the right. This can be tweaked (as in the picture) without changing the mode's behavior
- **Navigation/scrolling shortcuts** that work without point ever having to leave the Org buffer:
  - `s-n` to open the next file
  - `s-p` to open the previous file
  - `s-r` to open a random file
  - `F8` to page down or, if at the end of a document, open the next one
  - `F7` to page up or, if at the beginning of a document, open the previous one
- **Synchronization with the Org buffer**: When a new document is opened, if an Org headline exists for that document, point moves to that headline. If one doesn't exist, it's automatically appended to the end of the Org file with a `TOREAD` status. `s-.` on an Org headline opens the corresponding document if it exists.
- **Optional dark mode** because I'm not an animal.

This is obviously very specific to my own workflow and preferences (the `super` key, the Org headline formatting, etc.), and anyone using it would need to change stuff to suit them. I don't see any likelihood of enough interest to justify making the mode suitable for general use, but am interested to hear any feedback, keeping in mind that I'm not a developer and have only a beginner's understanding of Elisp and programming in general.

### The Prompt

```
I'd like to try a new project. This will be pretty ambitious, so I'll definitely need lots of help with the Elisp. But it's important that the experience be as educational as it is productive; I want to come away with a better understanding of Emacs and Elisp just as much as I want to come away with a working piece of software.

* The Background and the Problem

From time to time I like to read through document sets that have been made available by government agencies through FOIA, by the National Archives, by presidential libraries, etc. These usually take the form of lots of small pdf files with nondescriptive names (for example, with the JFK Assassination Records releases, something like "104-10071-10021.pdf"). I love to read these, not to try and piece together some conspiracy theory, but for the incredible, granular glimpses into history they provide. But there are some pain points:

- for such a multitude of such small documents, simply opening, closing, navigating to the next, etc., takes up a significant amount of time and consistently breaks flow
- keeping track of what I've read and what I haven't becomes difficult when the sets are so large; renaming so many files in a meaningful way is impossible and probably pointless, since I'm unlikely to revisit any particular file; this isn't an academic project but an exercise in historical immersion (sort of)
- I would like to take notes on the files, using my typical org-mode "TOREAD/READING/READ" system, but making a headline for each file would be very tedious

* The Solution

It occurs to me that Emacs would be an ideal environment in which to construct a workflow that would solve each pain point and provide a unified interface for navigating, reading, tracking, and taking notes on these files in a smooth, streamlined way. This would involve:

- a standard window layout: in fullscreen (my monitor is 1920x1080), this would be: a narrow Dired buffer on the far left, listing the files (which are collected in a directory); a pdf-view buffer directly to the right, showing the document; and on the right side of the frame, an org-mode buffer containing my notes, with maybe a second buffer below as needed for web searches, other notes, etc.
- a set of keybindings and functions for navigation and behavior:
  - `s-n` would advance to the next file in the directory, opening it in the document window (killing the document buffer currently displayed), `s-p` would open the previous document, and `s-r` would open a random document in the directory 
  - `F8` would, as in other contexts in my Emacs config, scroll or page forward, but at the end of a document would advance to the next document as if `s-n` had been pressed; `F7` the same, backward
  - when a document is opened, either move point in the org-mode buffer to an existing "TOREAD/READING/READ" headline containing the filename, or, if one doesn't exist, append a new headline to the file: "* TOREAD {filename}", moving point there (I should be able to navigate and edit anywhere in the org file in the meantime, but any change in the active document in the pdf-view buffer should snap point to its associated headline)
  - in all of these operations, point shouldn't move from the org buffer (other than what's momentarily necessary to execute a step in a function, and then it should always return to the org buffer)

Based on my limited knowledge of Elisp and Emacs, my guess is that this would be best achieved by creating a minor mode? I don't know how else (or how, really) to coordinate behavior between different windows showing buffers in different modes. Anyway, is this feasible? If so, how would you suggest attacking it?
```
