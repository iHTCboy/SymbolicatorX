//
//  FileBrowserViewController.swift
//  SymbolicatorX
//
//  Created by 钟晓跃 on 2020/7/27.
//  Copyright © 2020 钟晓跃. All rights reserved.
//

import Cocoa

class FileBrowserViewController: BaseViewController {
    
    private let devicePopBtn = NSPopUpButton()
    private let appPopBtn = NSPopUpButton()
    private let outlineView = NSOutlineView()
    private var exportBtn: NSButton!
    
    private var deviceList = [Device]() {
        willSet {
            var deviceNameList = [String]()
            self.deviceList = newValue.filter { (device) -> Bool in
                
                guard
                    var lockdownClient = try? LockdownClient(device: device, withHandshake: false),
                    let deviceName = try? lockdownClient.getName()
                else { return false }
                
                deviceNameList.append(deviceName)
                lockdownClient.free()
                return true
            }
            
            DispatchQueue.main.async {
                self.devicePopBtn.removeAllItems()
                self.devicePopBtn.addItems(withTitles: deviceNameList)
                self.selectLastDevice()
                self.initAppData()
            }
        }
    }
    
    private var appInfoDict = [String:Plist]() {
        didSet {
            DispatchQueue.main.async {
                self.appPopBtn.removeAllItems()
                self.appPopBtn.addItems(withTitles: self.appInfoDict.keys.sorted())
                self.selectLastProcess()
                self.initFileData()
            }
        }
    }
    
    private var file: FileModel?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
        setupUI()
        initDeviceData()
    }
    
}

// MARK: - Init Data
extension FileBrowserViewController {
    
    private func initDeviceData() {
        DispatchQueue.global().async {
            guard let deviceList = try? MobileDevice.getDeviceList().compactMap({ (udid) -> Device? in
                try? Device(udid: udid)
            }) else { return }
            
            self.deviceList = deviceList
        }
    }
    
    private func initAppData() {
        
        guard
            deviceList.count > 0,
            devicePopBtn.indexOfSelectedItem < deviceList.count
            else { return }
        let device = deviceList[devicePopBtn.indexOfSelectedItem]
        lastSelectedDeviceUDID = try? device.getUDID()
        
        DispatchQueue.global().async {
            
            let options = Plist(dictionary: ["ApplicationType":Plist(string: "User")])
            do {
                var lockdownClient = try LockdownClient(device: device, withHandshake: true)
                var installService = try lockdownClient.getService(service: .installationProxy)
                var install = try InstallationProxy(device: device, service: installService)
                let appListPlist = try install.browse(options: options)
                
                var appInfoDict = [String:Plist]()
                _ = appListPlist.array?.compactMap({ (appInfoItem) -> Plist? in
                    
                    guard
                        let signer = appInfoItem["SignerIdentity"]?.string,
                        signer.contains("Developer") || signer.contains("Development"),
                        let appName = appInfoItem["CFBundleDisplayName"]?.string
                    else { return nil }
                    
                    appInfoDict[appName] = appInfoItem
                    
                    return appInfoItem
                })
                self.appInfoDict = appInfoDict
                
                lockdownClient.free()
                installService.free()
                install.free()
            } catch {
                print(error)
            }
        }
    }
    
    private func initFileData() {
        
        guard
            deviceList.count > 0,
            devicePopBtn.indexOfSelectedItem < deviceList.count,
            appPopBtn.indexOfSelectedItem < appInfoDict.count
        else { return }
        
        let device = deviceList[devicePopBtn.indexOfSelectedItem]
        let title = appPopBtn.selectedItem?.title ?? ""
        let appInfo = appInfoDict[title]
        let process = appInfo?["CFBundleExecutable"]?.string ?? ""
        lastSelectedProcess = process
        
        guard let appID = appInfo?["CFBundleIdentifier"]?.string else { return }
        
        DispatchQueue.global().async {
            do {
                let lockdownClient = try LockdownClient(device: device, withHandshake: true)
                let lockdownService = try lockdownClient.getService(service: .houseArrest)
                let houseArrest = try HouseArrest(device: device, service: lockdownService)
                try houseArrest.sendCommand(command: "VendContainer", appid: appID)
                _ = try houseArrest.getResult()
                let afcClient = try AfcClient(houseArrest: houseArrest)
                let fileInfo = try afcClient.getFileInfo(path: ".")
                self.file = FileModel(filePath: ".", fileInfo: fileInfo, afcClient: afcClient)
                DispatchQueue.main.async {
                    self.outlineView.reloadData()
                }
            } catch {
                print(error)
            }
        }
    }
}

// MARK: - Action
extension FileBrowserViewController {
    
    @objc private func didClickBackBtn() {
        
        guard
            let window = view.window,
            let parent = window.parent
        else { return }
        
        parent.endSheet(window)
    }
    
    @objc private func didClickExportBtn() {
        
        guard let file = outlineView.item(atRow: outlineView.selectedRow) as? FileModel else { return }
        
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = file.name
        savePanel.beginSheetModal(for: view.window!) { (response) in
            
            switch response {
            case .OK:
                guard let url = savePanel.url else { return }
                file.save(toPath: url)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            default:
                return
            }
        }
    }
    
    @objc private func didChangeDevice(_ sender: NSPopUpButton) {
        
        initAppData()
    }
    
    @objc private func didChangeApp(_ sender: NSPopUpButton) {
        
        initFileData()
    }
    
}

// MARK: - NSOutlineViewDataSource
extension FileBrowserViewController: NSOutlineViewDataSource {
    
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        
        if let file = item as? FileModel {
            
            return file.children.count
        } else {
            
            return file?.children.count ?? 0
        }
    }
    
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        
        if let file = item as? FileModel {
            
            return file.children[index]
        } else {
            
            return file!.children[index]
        }
    }
    
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        
        let file = item as! FileModel
        
        return file.children.count > 0
    }
}

// MARK: - NSOutlineViewDelegate
extension FileBrowserViewController: NSOutlineViewDelegate {
    
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        
        var cell: NSTableCellView?
        let file = item as? FileModel
        if tableColumn == outlineView.tableColumns[0] {
            
            cell = (outlineView.makeView(withIdentifier: .file, owner: nil) as? FileTableCellView) ?? FileTableCellView()
            (cell as! FileTableCellView).model = file
        } else {
            
            cell = NSTableCellView.makeCellView(tableView: outlineView, identifier: .date)
            cell?.textField?.stringValue = file?.dateStr ?? ""
        }
        
        return cell
    }
    
    func outlineViewSelectionDidChange(_ notification: Notification) {
        exportBtn.isEnabled = outlineView.selectedRowIndexes.count > 0
    }
    
}

// MARK: - Restory Last Selected
extension FileBrowserViewController {
    
    var lastSelectedDeviceUDID: String? {
        get {
            UserDefaults.standard.string(forKey: "lastSelectedDeviceUDID")
        }
        set{
            UserDefaults.standard.setValue(newValue, forKey: "lastSelectedDeviceUDID")
        }
    }
    
    var lastSelectedProcess: String? {
        get {
            UserDefaults.standard.string(forKey: "lastSelectedProcess")
        }
        set{
            UserDefaults.standard.setValue(newValue, forKey: "lastSelectedProcess")
        }
    }
    
    private func selectLastDevice() {
        
        guard let lastUDID = lastSelectedDeviceUDID else { return }
        
        let index = deviceList.firstIndex { (device) -> Bool in
            guard let udid = try? device.getUDID() else { return false }
            
            return udid == lastUDID
        }
        
        devicePopBtn.selectItem(at: index ?? 0)
    }
    
    private func selectLastProcess() {
        
        guard let lastProcess = lastSelectedProcess else { return }
        
        let appInfo = appInfoDict.values.first { (appInfo) -> Bool in
            guard let process = appInfo["CFBundleExecutable"]?.string else { return false }
            
            return process == lastProcess
        }
        
        if let appName = appInfo?["CFBundleDisplayName"]?.string {
            appPopBtn.selectItem(withTitle: appName)
        }
    }
}

// MARK: - UI
extension FileBrowserViewController {
    
    private func setupUI() {
        
        exportBtn = NSButton.makeButton(title: "Export", target: self, action: #selector(didClickExportBtn))
        exportBtn.isEnabled = false
        view.addSubview(exportBtn)
        exportBtn.snp.makeConstraints { (make) in
            make.right.equalToSuperview().offset(-10)
            make.top.equalToSuperview().offset(10)
        }
        
        let back = NSButton.makeButton(title: "Back", target: self, action: #selector(didClickBackBtn))
        view.addSubview(back)
        back.snp.makeConstraints { (make) in
            make.right.equalTo(exportBtn.snp.left).offset(-10)
            make.top.equalTo(exportBtn)
        }
        
        devicePopBtn.target = self
        devicePopBtn.action = #selector(didChangeDevice(_:))
        devicePopBtn.focusRingType = .none
        view.addSubview(devicePopBtn)
        devicePopBtn.snp.makeConstraints { (make) in
            make.top.left.equalToSuperview().offset(10)
            make.width.equalTo(120)
        }
        
        appPopBtn.target = self
        appPopBtn.action = #selector(didChangeApp(_:))
        appPopBtn.focusRingType = .none
        view.addSubview(appPopBtn)
        appPopBtn.snp.makeConstraints { (make) in
            make.top.equalTo(devicePopBtn)
            make.left.equalTo(devicePopBtn.snp.right).offset(10)
            make.width.equalTo(285)
        }
        
        let column1 = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(rawValue: "name"))
        column1.title = "name"
        column1.width = 420
        column1.maxWidth = 450
        column1.minWidth = 160
        outlineView.addTableColumn(column1)
        
        let column2 = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(rawValue: "date"))
        column2.title = "date"
        column2.width = 160
        outlineView.addTableColumn(column2)
        
        outlineView.usesAlternatingRowBackgroundColors = true
        outlineView.delegate = self;
        outlineView.dataSource = self;
        outlineView.focusRingType = .none
        outlineView.rowHeight = 20
        outlineView.outlineTableColumn = column1
        
        let scrollView = NSScrollView()
        scrollView.focusRingType = .none
        scrollView.borderType = .bezelBorder
        scrollView.autohidesScrollers = true
        scrollView.documentView = outlineView
        view.addSubview(scrollView)
        scrollView.snp.makeConstraints { (make) in
            make.bottom.right.equalToSuperview().offset(-10)
            make.left.equalToSuperview().offset(10)
            make.top.equalTo(devicePopBtn.snp.bottom).offset(10)
        }
    }
}