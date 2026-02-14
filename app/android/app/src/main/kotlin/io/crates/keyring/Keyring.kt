package io.crates.keyring

import android.content.Context

class Keyring {
    companion object {
        init {
            System.loadLibrary("rust_lib_burrow_app")
        }

        external fun initializeNdkContext(context: Context)
    }
}
