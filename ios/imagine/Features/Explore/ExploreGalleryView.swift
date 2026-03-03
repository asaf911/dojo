//
//  ExploreGalleryView.swift
//  Dojo
//
//  Created by Asaf Shamir on 2025-02-13
//

import SwiftUI

enum PracticeFilterType {
    case duration(Int)
    case tag(String)
}

struct ExploreGalleryView: View {
    let audioFiles: [AudioFile]
    /// Remove the local selectedFile from parent and pass the manager's instead:
    @Binding var selectedFile: AudioFile?
    
    @ObservedObject var audioPlayerManager: AudioPlayerManager
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @EnvironmentObject var navigationCoordinator: NavigationCoordinator
    
    @State private var selectedDuration: Int? = nil
    @State private var selectedTag: String? = nil
    
    // Unique tags & durations
    var uniqueTags: [String] {
        let tags = audioFiles.flatMap { $0.tags }
        let uniqueTagsSet = Set(tags)
        let inDefaultSequence = defaultTagSequence.filter { uniqueTagsSet.contains($0) }
        let notInDefaultSequence = uniqueTagsSet.subtracting(defaultTagSequence).sorted()
        return inDefaultSequence + notInDefaultSequence
    }
    
    var uniqueDurations: [Int] {
        let durations = audioFiles.flatMap { $0.durations.map { $0.length } }
        return Array(Set(durations)).sorted()
    }
    
    // Filtered list
    var filteredAudioFiles: [AudioFile] {
        audioFiles.filter { audioFile in
            var matchesDuration = true
            var matchesTag = true
            
            if let selectedDuration = selectedDuration {
                matchesDuration = audioFile.durations.contains { $0.length == selectedDuration }
            }
            if let selectedTag = selectedTag {
                matchesTag = audioFile.tags.contains(selectedTag)
            }
            return matchesDuration && matchesTag
        }
    }
    
    var body: some View {
        VStack {
            filterSection
            ScrollView(.vertical, showsIndicators: false) {
                Spacer().frame(height: 25)
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(filteredAudioFiles) { audioFile in
                        PracticeItemView(
                            audioFile: audioFile,
                            selectedFile: $selectedFile,
                            audioPlayerManager: audioPlayerManager,
                            subscriptionManager: subscriptionManager
                        )
                        .id(audioFile.id)
                    }
                }
                // Footer clearance handled by DojoScreenContainer
                Spacer().frame(height: HeaderLayout.footerClearance)
            }
            .topFadeMask(height: 5)
        }
        // Ensure the outer container aligns its children at the top.
        .frame(maxHeight: .infinity, alignment: .top)
    }
    
    @ViewBuilder
    private var filterSection: some View {
        VStack(spacing: 15) {
            // Horizontal ScrollView for duration filters
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    Rectangle().fill(.clear).frame(width: 10)
                    FilterOptionView(
                        text: "All",
                        isSelected: selectedDuration == nil && selectedTag == nil,
                        action: {
                            selectedDuration = nil
                            selectedTag = nil
                        },
                        isDurationFilter: true,
                        source: "ExploreGalleryView"
                    )
                    .padding(.trailing, 8)
                    
                    ForEach(uniqueDurations, id: \.self) { duration in
                        FilterOptionView(
                            text: "\(duration) m",
                            isSelected: selectedDuration == duration,
                            action: {
                                selectedDuration = duration
                                selectedTag = nil
                            },
                            isDurationFilter: true,
                            source: "ExploreGalleryView"
                        )
                        .padding(.trailing, 8)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.horizontal, -26)
            .frame(height: 27, alignment: .top)

            // Horizontal ScrollView for tag filters
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    Rectangle().fill(.clear).frame(width: 10)
                    
                    ForEach(uniqueTags, id: \.self) { tag in
                        FilterOptionView(
                            text: tag,
                            isSelected: selectedTag == tag,
                            action: {
                                selectedTag = tag
                                selectedDuration = nil
                            },
                            isDurationFilter: false,
                            source: "ExploreGalleryView"
                        )
                        .padding(.trailing, 8)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.horizontal, -26)
            .frame(height: 27, alignment: .top)
        }
    }
    
    private let columns = [
        GridItem(.flexible(), spacing: 16)
    ]
    
    private let defaultTagSequence = ["Stress relief", "Sleep", "Breath work"]
}

struct ExploreGalleryView_Previews: PreviewProvider {
    static var previews: some View {
        let sampleAudioFiles = [
            AudioFile(
                id: "sample1",
                title: "Sample Audio 1",
                category: .relax,
                description: "Sample Description 1",
                imageFile: "https://via.placeholder.com/150",
                durations: [
                    Duration(length: 5, fileName: "sample-5m.mp3"),
                    Duration(length: 10, fileName: "sample-10m.mp3")
                ],
                premium: false,
                tags: ["relaxation", "quick"]
            ),
            AudioFile(
                id: "sample2",
                title: "Sample Audio 2",
                category: .relax,
                description: "Sample Description 2",
                imageFile: "https://via.placeholder.com/150",
                durations: [
                    Duration(length: 15, fileName: "sample-15m.mp3"),
                    Duration(length: 20, fileName: "sample-20m.mp3")
                ],
                premium: false,
                tags: ["focus", "meditation"]
            ),
            AudioFile(
                id: "sample3",
                title: "Sample Audio 3",
                category: .relax,
                description: "Sample Description 3",
                imageFile: "https://via.placeholder.com/150",
                durations: [
                    Duration(length: 25, fileName: "sample-25m.mp3"),
                    Duration(length: 30, fileName: "sample-30m.mp3")
                ],
                premium: false,
                tags: ["deep relaxation", "body scan"]
            )
        ]
        
        ExploreGalleryView(
            audioFiles: sampleAudioFiles,
            selectedFile: .constant(nil),
            audioPlayerManager: AudioPlayerManager()
        )
        .environmentObject(SubscriptionManager.shared)
        .environmentObject(NavigationCoordinator())
        .previewLayout(.sizeThatFits)
        .background(Color.backgroundDarkPurple)
    }
}
