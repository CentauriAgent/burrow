//! GStreamer WebRTC pipeline for headless audio calls.
//!
//! Creates a GStreamer pipeline with `webrtcbin` for P2P audio:
//!
//! ```text
//! Outbound: pulsesrc → opusenc → rtpopuspay → webrtcbin
//! Inbound:  webrtcbin → rtpopusdepay → opusdec → pulsesink
//! ```
//!
//! In pipe mode (for AI agent), replaces pulsesrc/pulsesink with
//! filesrc/filesink reading/writing raw PCM from named pipes.

#![cfg(feature = "webrtc")]

use anyhow::{Context, Result};
use gstreamer as gst;
use gstreamer::prelude::*;
use gstreamer_sdp as gst_sdp;
use gstreamer_webrtc as gst_webrtc;
use std::sync::{Arc, Mutex};
use tokio::sync::mpsc;

/// ICE candidate gathered by webrtcbin, ready to send to remote peer.
#[derive(Debug, Clone)]
pub struct IceCandidate {
    pub candidate: String,
    pub sdp_m_line_index: u32,
}

/// Events from the WebRTC pipeline to the signaling layer.
#[derive(Debug)]
pub enum WebRtcEvent {
    /// SDP offer created (for initiator)
    OfferCreated(String),
    /// SDP answer created (for answerer)
    AnswerCreated(String),
    /// Local ICE candidate gathered
    IceCandidateGathered(IceCandidate),
    /// Peer connection state changed
    StateChanged(String),
    /// Error occurred
    Error(String),
}

/// A headless WebRTC audio session using GStreamer.
pub struct WebRtcSession {
    pipeline: gst::Pipeline,
    webrtcbin: gst::Element,
    event_tx: mpsc::UnboundedSender<WebRtcEvent>,
}

impl WebRtcSession {
    /// Create a new WebRTC session.
    ///
    /// `pipe_mode`: If Some("input:output"), use file pipes instead of PulseAudio.
    /// `event_tx`: Channel to send WebRTC events to the signaling layer.
    pub fn new(
        pipe_mode: Option<&str>,
        event_tx: mpsc::UnboundedSender<WebRtcEvent>,
    ) -> Result<Self> {
        gst::init().context("Failed to initialize GStreamer")?;

        let pipeline = gst::Pipeline::new();

        // Create webrtcbin element
        let webrtcbin = gst::ElementFactory::make("webrtcbin")
            .name("webrtcbin")
            .property_from_str("bundle-policy", "max-bundle")
            .build()
            .context("Failed to create webrtcbin (is gst-plugins-bad installed?)")?;

        // Add STUN server for NAT traversal
        webrtcbin.set_property_from_str("stun-server", "stun://stun.l.google.com:19302");

        pipeline.add(&webrtcbin).context("Failed to add webrtcbin to pipeline")?;

        // Build audio source pipeline
        let (audio_src, audio_enc, rtp_pay) = if let Some(pipes) = pipe_mode {
            // Pipe mode: read raw PCM from a file/pipe
            let parts: Vec<&str> = pipes.split(':').collect();
            let input_path = parts.first().copied().unwrap_or("/dev/null");

            let src = gst::ElementFactory::make("filesrc")
                .property("location", input_path)
                .build()
                .context("Failed to create filesrc")?;
            let capsfilter = gst::ElementFactory::make("capsfilter")
                .property(
                    "caps",
                    &gst::Caps::builder("audio/x-raw")
                        .field("format", "S16LE")
                        .field("rate", 48000i32)
                        .field("channels", 1i32)
                        .build(),
                )
                .build()
                .context("Failed to create capsfilter")?;
            let enc = gst::ElementFactory::make("opusenc")
                .property("bitrate", 32000i32)
                .property("audio-type", 2048i32) // voice
                .build()
                .context("Failed to create opusenc")?;
            let pay = gst::ElementFactory::make("rtpopuspay")
                .property("pt", 111u32)
                .build()
                .context("Failed to create rtpopuspay")?;

            pipeline.add_many([&src, &capsfilter, &enc, &pay])
                .context("Failed to add source elements")?;
            gst::Element::link_many([&src, &capsfilter, &enc, &pay])
                .context("Failed to link source elements")?;

            (src, enc, pay)
        } else {
            // PulseAudio/PipeWire mode: capture from system mic
            let src = gst::ElementFactory::make("pulsesrc")
                .build()
                .or_else(|_| gst::ElementFactory::make("autoaudiosrc").build())
                .context("Failed to create audio source (pulsesrc or autoaudiosrc)")?;
            let enc = gst::ElementFactory::make("opusenc")
                .property("bitrate", 32000i32)
                .property("audio-type", 2048i32)
                .build()
                .context("Failed to create opusenc")?;
            let pay = gst::ElementFactory::make("rtpopuspay")
                .property("pt", 111u32)
                .build()
                .context("Failed to create rtpopuspay")?;

            pipeline.add_many([&src, &enc, &pay])
                .context("Failed to add source elements")?;
            gst::Element::link_many([&src, &enc, &pay])
                .context("Failed to link source elements")?;

            (src, enc, pay)
        };

        // Link RTP payloader to webrtcbin
        let webrtc_sink = webrtcbin
            .request_pad_simple("sink_%u")
            .context("Failed to get webrtcbin sink pad")?;
        let pay_src = rtp_pay
            .static_pad("src")
            .context("Failed to get rtpopuspay src pad")?;
        pay_src.link(&webrtc_sink)
            .map_err(|e| anyhow::anyhow!("Failed to link to webrtcbin: {:?}", e))?;

        // Handle incoming audio from remote peer
        let pipeline_weak = pipeline.downgrade();
        let pipe_mode_owned = pipe_mode.map(|s| s.to_string());
        webrtcbin.connect_pad_added(move |_, pad| {
            let Some(pipeline) = pipeline_weak.upgrade() else { return };
            let caps = match pad.current_caps() {
                Some(c) => c,
                None => return,
            };
            let s = caps.structure(0);
            let is_audio = s.map_or(false, |s| {
                s.name().as_str().starts_with("application/x-rtp")
                    && s.get::<&str>("media").unwrap_or("") == "audio"
            });
            if !is_audio {
                return;
            }

            // Build decode pipeline for incoming audio
            let depay = gst::ElementFactory::make("rtpopusdepay")
                .build().expect("rtpopusdepay");
            let dec = gst::ElementFactory::make("opusdec")
                .build().expect("opusdec");

            let sink = if let Some(ref pipes) = pipe_mode_owned {
                let parts: Vec<&str> = pipes.split(':').collect();
                let output_path = parts.get(1).copied().unwrap_or("/dev/null");
                let convert = gst::ElementFactory::make("audioconvert")
                    .build().expect("audioconvert");
                let capsfilter = gst::ElementFactory::make("capsfilter")
                    .property(
                        "caps",
                        &gst::Caps::builder("audio/x-raw")
                            .field("format", "S16LE")
                            .field("rate", 48000i32)
                            .field("channels", 1i32)
                            .build(),
                    )
                    .build().expect("capsfilter");
                let filesink = gst::ElementFactory::make("filesink")
                    .property("location", output_path)
                    .build().expect("filesink");

                pipeline.add_many([&depay, &dec, &convert, &capsfilter, &filesink]).unwrap();
                gst::Element::link_many([&depay, &dec, &convert, &capsfilter, &filesink]).unwrap();
                filesink.sync_state_with_parent().unwrap();
                capsfilter.sync_state_with_parent().unwrap();
                convert.sync_state_with_parent().unwrap();
                filesink
            } else {
                let sink = gst::ElementFactory::make("pulsesink")
                    .build()
                    .or_else(|_| gst::ElementFactory::make("autoaudiosink").build())
                    .expect("audio sink");
                pipeline.add_many([&depay, &dec, &sink]).unwrap();
                gst::Element::link_many([&depay, &dec, &sink]).unwrap();
                sink.sync_state_with_parent().unwrap();
                sink
            };

            depay.sync_state_with_parent().unwrap();
            dec.sync_state_with_parent().unwrap();

            let depay_sink = depay.static_pad("sink").unwrap();
            pad.link(&depay_sink).unwrap();
        });

        // ICE candidate gathering callback
        let tx = event_tx.clone();
        webrtcbin.connect("on-ice-candidate", false, move |args| {
            let sdp_m_line_index = args[1].get::<u32>().unwrap();
            let candidate = args[2].get::<String>().unwrap();
            let _ = tx.send(WebRtcEvent::IceCandidateGathered(IceCandidate {
                candidate,
                sdp_m_line_index,
            }));
            None
        });

        Ok(Self {
            pipeline,
            webrtcbin,
            event_tx,
        })
    }

    /// Create and set a local SDP offer (caller side).
    pub async fn create_offer(&self) -> Result<String> {
        let webrtcbin = self.webrtcbin.clone();
        let tx = self.event_tx.clone();

        let promise = gst::Promise::with_change_func(move |reply| {
            let reply = match reply {
                Ok(Some(reply)) => reply,
                _ => return,
            };
            let offer = reply
                .value("offer")
                .expect("no offer in reply")
                .get::<gst_webrtc::WebRTCSessionDescription>()
                .expect("invalid offer type");

            let sdp_text = offer.sdp().to_string();
            webrtcbin.emit_by_name::<()>("set-local-description", &[&offer, &None::<gst::Promise>]);
            let _ = tx.send(WebRtcEvent::OfferCreated(sdp_text));
        });

        self.webrtcbin
            .emit_by_name::<()>("create-offer", &[&None::<gst::Structure>, &promise]);

        Ok(String::new()) // Actual SDP comes via event channel
    }

    /// Set the remote SDP offer and create an answer (answerer side).
    pub async fn set_remote_offer_and_answer(&self, sdp_offer: &str) -> Result<String> {
        let sdp = gst_sdp::SDPMessage::parse_buffer(sdp_offer.as_bytes())
            .map_err(|_| anyhow::anyhow!("Failed to parse remote SDP offer"))?;
        let offer = gst_webrtc::WebRTCSessionDescription::new(
            gst_webrtc::WebRTCSDPType::Offer,
            sdp,
        );

        self.webrtcbin
            .emit_by_name::<()>("set-remote-description", &[&offer, &None::<gst::Promise>]);

        // Create answer
        let webrtcbin = self.webrtcbin.clone();
        let tx = self.event_tx.clone();

        let promise = gst::Promise::with_change_func(move |reply| {
            let reply = match reply {
                Ok(Some(reply)) => reply,
                _ => return,
            };
            let answer = reply
                .value("answer")
                .expect("no answer in reply")
                .get::<gst_webrtc::WebRTCSessionDescription>()
                .expect("invalid answer type");

            let sdp_text = answer.sdp().to_string();
            webrtcbin.emit_by_name::<()>("set-local-description", &[&answer, &None::<gst::Promise>]);
            let _ = tx.send(WebRtcEvent::AnswerCreated(sdp_text));
        });

        self.webrtcbin
            .emit_by_name::<()>("create-answer", &[&None::<gst::Structure>, &promise]);

        Ok(String::new())
    }

    /// Set the remote SDP answer (caller side, after receiving answer).
    pub fn set_remote_answer(&self, sdp_answer: &str) -> Result<()> {
        let sdp = gst_sdp::SDPMessage::parse_buffer(sdp_answer.as_bytes())
            .map_err(|_| anyhow::anyhow!("Failed to parse remote SDP answer"))?;
        let answer = gst_webrtc::WebRTCSessionDescription::new(
            gst_webrtc::WebRTCSDPType::Answer,
            sdp,
        );

        self.webrtcbin
            .emit_by_name::<()>("set-remote-description", &[&answer, &None::<gst::Promise>]);
        Ok(())
    }

    /// Add a remote ICE candidate.
    pub fn add_ice_candidate(&self, sdp_m_line_index: u32, candidate: &str) {
        self.webrtcbin
            .emit_by_name::<()>("add-ice-candidate", &[&sdp_m_line_index, &candidate]);
    }

    /// Start the pipeline (begin media flow).
    pub fn start(&self) -> Result<()> {
        self.pipeline
            .set_state(gst::State::Playing)
            .map_err(|e| anyhow::anyhow!("Failed to start pipeline: {:?}", e))?;
        eprintln!("🎙️ Audio pipeline started");
        Ok(())
    }

    /// Stop the pipeline.
    pub fn stop(&self) {
        let _ = self.pipeline.set_state(gst::State::Null);
        eprintln!("🔇 Audio pipeline stopped");
    }
}

impl Drop for WebRtcSession {
    fn drop(&mut self) {
        self.stop();
    }
}
