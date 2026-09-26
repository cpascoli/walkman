import Foundation
import FoundationModels

/// Asks Apple's on-device language model what song a video is.
enum OnDeviceModel {

    @Generable
    struct Reading {
        @Guide(description: "True only if the video is one song or piece of music. False for concerts, DJ sets, compilations, playlists, tutorials, reviews, vlogs and anything that isn't music.")
        var isSingleSong: Bool
        @Guide(description: "The artist, band or composer who made the song, in the usual Latin spelling. Empty if not a single song.")
        var artist: String
        @Guide(description: "The song's title alone: no artist, no 'Official Video', 'Lyrics', 'Remastered', 'Live', 'slowed' or other extras. Empty if not a single song.")
        var track: String
    }

    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    static func read(_ video: SearchResult, credit: MusicCredit?) async throws -> Reading {
        let session = LanguageModelSession(instructions: """
            You identify songs from YouTube video details for a music app. \
            Use what you know about music: soundtracks and classical pieces have a composer, \
            and uploads by fans or labels often don't name the artist in the channel. \
            YouTube's music credit, when given, lists music heard in the video, which may be background music.
            """)
        var prompt = """
            Title: \(video.title)
            Channel: \(video.channel)
            Length: \(video.duration.isEmpty ? "live stream" : video.duration)
            """
        if let credit {
            prompt += "\nYouTube music credit: \(credit.song) by \(credit.artist)"
        }
        // Greedy sampling: the same video always gets the same reading.
        return try await session.respond(to: prompt, generating: Reading.self,
                                         options: GenerationOptions(sampling: .greedy)).content
    }
}
