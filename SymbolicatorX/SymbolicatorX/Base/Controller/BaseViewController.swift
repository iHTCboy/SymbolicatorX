//
//  BaseViewController.swift
//  SymbolicatorX
//
//  Created by 钟晓跃 on 2020/7/5.
//  Copyright © 2020 钟晓跃. All rights reserved.
//

import Cocoa

class BaseViewController: NSViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
//        view.wantsLayer = true
//        view.layer?.backgroundColor = NSColor.white.cgColor
    }
    
    override func loadView() {
        view = NSView()
    }
    
}
