//
//  PAAudioToolkit.swift
//
//  Copyright © 2015 Patrick Angle.
//  All rights reserved.
//
//  Redistribution and use in source and binary forms, with or without modification,
//  are permitted provided that the following conditions are met:
//
//  1. Redistributions of source code must retain the above copyright notice, this
//     list of conditions and the following disclaimer.
//
//  2. Redistributions in binary form must reproduce the above copyright notice,
//     this list of conditions and the following disclaimer in the documentation
//     and/or other materials provided with the distribution.
//
//  3. Neither the name of the copyright holder nor the names of its contributors
//     may be used to endorse or promote products derived from this software without
//     specific prior written permission.
//
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
//  ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
//  WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
//  IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
//  INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
//  NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
//  PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
//  WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
//  ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
//  POSSIBILITY OF SUCH DAMAGE.
//
//  Some code is derived from an article originally from Chris Adamson, posted here:
//  http://www.subfurther.com/blog/2010/12/13/from-ipod-library-to-pcm-samples-in-far-
//  fewer-steps-than-were-previously-necessary/, and has been updated to Swift 2.0 by
//  Patrick Angle.

import Foundation
import AudioToolbox
import AVFoundation
import MediaPlayer

class PAAudioToolkit {
    /// Fetch and convert the given `MPMediaItem` to an audio file in `kAudioFormatLinearPCM` format to the given destination `NSURL`. Be sure to clean up the file at `destination` if the import fails. This function will block the current thread until setup is complete and conversion begins, at which point it will kick conversion to the `QOS_USER_INITIATED` thread and return. You will be notified of completion, successful or otherwise by the `completionHandler` block.
    ///
    /// - parameter song: the `MPMediaItem` you wish to convert. The item must be present in the users library on the device, and must not have DRM applied.
    /// - parameter destination: the `NSURL` to which you wish to save the imported item.
    /// - parameter completionHandler: the `(success: Bool, errorMessage: String?) -> Void` block to handle completion of the conversion. `success` is `true` when the song was imported without issue and the file at `destination` is now available. If `success` is `false` the song was not imported sucessfully, and the file at `destination` either will not exist or will be corrupt. If `false` is returned for success, an accompanying `errorMessage` will be provided. `errorMessage` will be nil if the operation is successful.
    /// - note: `completionHandler` will be called on the current thread, unless the operation is successful, in which case it will be called on the `QOS_USER_INTERACTIVE` thread. Keep this in mind if you plan to affect the user interface inside the `completionHandler`.
    class func importMusicLibraryItem(song: MPMediaItem, destination: NSURL, completionHandler: (success: Bool, errorMessage: String?) -> Void) {
        let assetURL = song.assetURL!
        let songAsset = AVURLAsset(URL: assetURL)
        
        var assetReader: AVAssetReader
        do {
            assetReader = try AVAssetReader(asset: songAsset)
        } catch let error as NSError {
            print("PAAudioToolkit > Failed to create AVAssetReader: \(error.description)")
            completionHandler(success: false, errorMessage: error.localizedFailureReason)
            return
        }
        
        let assetReaderOutput = AVAssetReaderAudioMixOutput(audioTracks: songAsset.tracks, audioSettings: nil)
        
        if !assetReader.canAddOutput(assetReaderOutput) {
            print("PAAudioToolkit > Unable to add AVAssetReaderOutput to AVAssetReader.")
            completionHandler(success: false, errorMessage: "The song can not be read. Ensure the song is on your device and is DRM-free.")
            return
        }
    
        assetReader.addOutput(assetReaderOutput)
        
        if NSFileManager.defaultManager().fileExistsAtPath(destination.path!) {
            print("PAAudioToolkit > File already exists at destination: \(destination.path)")
            completionHandler(success: false, errorMessage: "A song of the same name already exists at the destination. Remove the file at the destination and try again.")
            return
        }
        
        var assetWriter: AVAssetWriter
        
        do {
            assetWriter = try AVAssetWriter(URL: destination, fileType: AVFileTypeAIFF)
        } catch let error as NSError {
            print("PAAudioToolkit > Failed to creatre AVAssetWriter: \(error.description)")
            completionHandler(success: false, errorMessage: error.localizedFailureReason)
            return
        }
        
        var channelLayout = AudioChannelLayout()
        channelLayout.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo
        
        let outputSettings: [String:AnyObject] = [
            AVFormatIDKey: NSNumber(unsignedInt: kAudioFormatLinearPCM),
            AVSampleRateKey: NSNumber(float: 44100.0),
            AVNumberOfChannelsKey: NSNumber(int: 2),
            AVChannelLayoutKey: NSData(bytes: &channelLayout, length: sizeof(AudioChannelLayout)),
            AVLinearPCMBitDepthKey: NSNumber(int: 16),
            AVLinearPCMIsNonInterleaved: NSNumber(bool: false),
            AVLinearPCMIsFloatKey: NSNumber(bool: false),
            AVLinearPCMIsBigEndianKey: NSNumber(bool: true)]
        
        let assetWriterInput = AVAssetWriterInput(mediaType: AVMediaTypeAudio, outputSettings: outputSettings)
        
        if !assetWriter.canAddInput(assetWriterInput) {
            print("PAAudioToolkit > Unable to add AVAssetWriterInput to AVAssetWriter.")
            completionHandler(success: false, errorMessage: "Unable to complete operation.")
            return
        }
        
        assetWriter.addInput(assetWriterInput)
        
        assetWriterInput.expectsMediaDataInRealTime = false
        
        assetWriter.startWriting()
        assetReader.startReading()
        
        let soundTrack = songAsset.tracks.first!
        let startTime = CMTimeMake(0, soundTrack.naturalTimeScale)
        assetWriter.startSessionAtSourceTime(startTime)
        
        assetWriterInput.requestMediaDataWhenReadyOnQueue(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0)) {
            while assetWriterInput.readyForMoreMediaData {
                if let nextBuffer = assetReaderOutput.copyNextSampleBuffer() {
                    assetWriterInput.appendSampleBuffer(nextBuffer)
                } else {
                    assetWriterInput.markAsFinished ()
                    assetWriter.finishWritingWithCompletionHandler() {
                        assetReader.cancelReading()
                        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0)) {
                            completionHandler(success: true, errorMessage: nil)
                        }
                    }
                }
            }
        }
        
        return
    }
}
