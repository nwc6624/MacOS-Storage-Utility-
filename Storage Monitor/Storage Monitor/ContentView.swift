//
//  ContentView.swift
//  Storage Monitor
//
//  Created by Noah Caulfield on 2/16/25.
import SwiftUI
import Foundation
import AppKit

// Function to get storage devices and their usage info
func getStorageDevices() -> [String: (total: Int64, free: Int64, used: Int64)] {
    var storageInfo: [String: (Int64, Int64, Int64)] = [:]
    
    let fileManager = FileManager.default
    let keys: [URLResourceKey] = [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]
    
    if let urls = fileManager.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: []) {
        for url in urls {
            do {
                let values = try url.resourceValues(forKeys: Set(keys))
                
                if let total = values.volumeTotalCapacity,
                   let free = values.volumeAvailableCapacity {
                    let used = total - free
                    storageInfo[url.path] = (Int64(total), Int64(free), Int64(used))
                }
            } catch {
                print("Error getting storage info for \(url.path): \(error)")
            }
        }
    }
    return storageInfo
}

struct ContentView: View {
    @State private var storageDevices: [String: (total: Int64, free: Int64, used: Int64)] = getStorageDevices()
    @State private var showAllVolumes = false
    @State private var showNetworkStorage = false
    @State private var monitor: DispatchSourceFileSystemObject?

    var body: some View {
        VStack {
            // Toggle Controls
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Show All Volumes", isOn: $showAllVolumes)
                        .toggleStyle(SwitchToggleStyle())

                    Toggle("Show Network Storage", isOn: $showNetworkStorage)
                        .toggleStyle(SwitchToggleStyle())
                }
                .padding(.leading)

                Spacer()

                Button(action: refreshStorage) {
                    Text("Refresh")
                        .bold()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor))
                        .foregroundColor(.white)
                }
                .padding()
            }
            .padding(.top)

            Text("Storage Overview")
                .font(.title)
                .bold()
                .padding(.vertical)

            ScrollView {
                LazyVStack(spacing: 12) {
                    if let internalStorage = detectInternalDrive() {
                        storageSection(title: "Internal Drive (/)", info: internalStorage.value, icon: "internaldrive.fill", color: .blue)
                    }

                    let externalDrives = storageDevices.filter { $0.key.hasPrefix("/Volumes/") && !isSystemPartition($0.key) && !isNetworkStorage($0.key) }
                    if !externalDrives.isEmpty {
                        Section(header: sectionHeader("External Storage")) {
                            ForEach(externalDrives.keys.sorted(), id: \.self) { device in
                                if let info = externalDrives[device] {
                                    storageSection(title: "External: \(device.replacingOccurrences(of: "/Volumes/", with: ""))", info: info, icon: "externaldrive.fill", color: .green)
                                }
                            }
                        }
                    }

                    if showAllVolumes {
                        let systemVolumes = storageDevices.filter { isSystemPartition($0.key) }
                        if !systemVolumes.isEmpty {
                            Section(header: sectionHeader("System Volumes")) {
                                ForEach(systemVolumes.keys.sorted(), id: \.self) { device in
                                    if let info = systemVolumes[device] {
                                        storageSection(title: device, info: info, icon: getSystemIcon(for: device), color: .gray)
                                    }
                                }
                            }
                        }
                    }

                    if showNetworkStorage {
                        Section(header: sectionHeader("Network Storage")) {
                            let networkVolumes = storageDevices.filter { isNetworkStorage($0.key) }
                            if networkVolumes.isEmpty {
                                Text("No network storage found")
                                    .italic()
                                    .foregroundColor(.gray)
                                    .padding()
                            } else {
                                ForEach(networkVolumes.keys.sorted(), id: \.self) { device in
                                    if let info = networkVolumes[device] {
                                        storageSection(title: "Network: \(device.replacingOccurrences(of: "/Volumes/", with: ""))", info: info, icon: "network", color: .purple)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .padding()
        .onAppear {
            refreshStorage()
            startMonitoringStorageChanges()
        }
    }

    private func refreshStorage() {
        storageDevices = getStorageDevices()
    }

    private func startMonitoringStorageChanges() {
        let volumesPath = "/Volumes"
        let fileDescriptor = open(volumesPath, O_EVTONLY)
        guard fileDescriptor != -1 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: .write,
            queue: DispatchQueue.main
        )

        source.setEventHandler {
            self.refreshStorage()
        }

        source.setCancelHandler {
            close(fileDescriptor)
        }

        source.resume()
        monitor = source

        // ✅ Also listen for drive insertions
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didMountNotification,
            object: nil,
            queue: .main
        ) { _ in
            self.refreshStorage()
        }
    }

    private func storageSection(title: String, info: (total: Int64, free: Int64, used: Int64), icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .foregroundColor(color)
                    .background(Circle().fill(Color.secondary.opacity(0.2)).frame(width: 36, height: 36))
                
                Text(title)
                    .font(.headline)
                    .bold()
            }
            
            Text("Total: \(formatSize(info.total))")
            Text("Used: \(formatSize(info.used))")
            Text("Free: \(formatSize(info.free))")

            ProgressView(value: Double(info.used), total: Double(info.total))
                .progressViewStyle(LinearProgressViewStyle(tint: color))
                .shadow(radius: 3)
                .frame(height: 10)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.15)))
        .padding(.horizontal)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.headline)
            .bold()
            .foregroundColor(.primary)
            .padding(.top, 10)
    }

    private func detectInternalDrive() -> (key: String, value: (total: Int64, free: Int64, used: Int64))? {
        if let rootDrive = storageDevices["/"] {
            return ("/", rootDrive)
        }
        return storageDevices.first(where: { !$0.key.hasPrefix("/Volumes/") })
    }

    private func formatSize(_ size: Int64) -> String {
        let gb = Double(size) / (1024 * 1024 * 1024)
        let mb = Double(size) / (1024 * 1024)
        let kb = Double(size) / 1024

        if gb >= 1 { return String(format: "%.2f GB", gb) }
        else if mb >= 1 { return String(format: "%.2f MB", mb) }
        else { return String(format: "%.2f KB", kb) }
    }
    
    
    // Identify system partitions
    private func isSystemPartition(_ path: String) -> Bool {
        let systemPaths = ["/System", "/Library", "/private", "/dev", "/Volumes/Recovery"]
        return systemPaths.contains { path.hasPrefix($0) }
    }

    // Get appropriate icon for system volumes
    private func getSystemIcon(for path: String) -> String {
        if path.hasPrefix("/System") {
            return "gearshape.fill"
        } else if path.hasPrefix("/Library") {
            return "books.vertical.fill"
        } else if path.hasPrefix("/private") {
            return "eye.slash.fill"
        } else if path.contains("Recovery") {
            return "lifepreserver.fill"
        }
        return "opticaldiscdrive.fill" // Default for other system volumes
    }

    // Identify network storage (mounted NAS drives)
    private func isNetworkStorage(_ path: String) -> Bool {
        return path.hasPrefix("/Volumes/") && (path.contains("afp") || path.contains("smb") || path.contains("nfs"))
    }

}
