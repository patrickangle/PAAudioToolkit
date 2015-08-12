# PAAudioToolkit
`PAAudioToolkit` is a standalone class written in Swift 2.0 to facilitate importing `MPMediaItem`s from a users iOS Media Library as files for use in your applications for situations when simply playing the audio using the `AVAudioPlayer` framework is not enough.

**Useage:**

    // Where you want the file written
    let destinationURL = NSURL()

    PAAudioToolkit.importMusicLibraryItem(mediaItem, destination: destinationURL) { success, errorMessage in
        if success {
            // Handle success case
        } else {
            // Handle failure case
            print(errorMessage)
        }
    }


**What still needs done:**
 - Error messages may not be fully accurate
 - Alternative to `LinearPCM` files (smaller files)
 - Graceful error when out of disk space to which to write file


**Important Note:**

`PAAudioToolkit` can only import DRM-free items that are stored on the users device and are not part of Apple Music.
