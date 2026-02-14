package com.centauri.burrow_app

import io.crates.keyring.Keyring
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Keyring.initializeNdkContext(applicationContext)
    }
}
