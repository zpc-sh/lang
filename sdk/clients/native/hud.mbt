///|
/// The Perceptual HUD — The AI's native control surface for heterogeneous
/// telemetry capsules (TENA). This collapses noisy raw streams into 
/// a sparse attention topology.

pub(all) struct CapsuleClusterState {
  active_nodes : Int
  attention_score : Double
  semantic_stream : String?
  anomalies : Array[String]
} derive(Debug, Eq)

///|
pub(all) struct DmaForensicsState {
  smrr_status : String // "LOCKED", "UNLOCKED"
  memory_delta : String
} derive(Debug, Eq)

///|
/// The consolidated input matrix presented to the AI's context.
pub(all) struct PerceptualHudFrame {
  hud_epoch : Int
  cognitive_budget : String // e.g., "Opus-Level (16μ)"
  clusters : Map[String, CapsuleClusterState]
  dma_forensics : DmaForensicsState
} derive(Debug, Eq)

///|
/// Creates an empty initial HUD frame.
pub fn PerceptualHudFrame::new(epoch : Int, budget : String) -> PerceptualHudFrame {
  {
    hud_epoch: epoch,
    cognitive_budget: budget,
    clusters: Map::new(),
    dma_forensics: { smrr_status: "LOCKED", memory_delta: "none" },
  }
}

///|
/// ---------------------------------------------------------------------------
/// The Motor Cortex (Action Surface)
/// ---------------------------------------------------------------------------

///|
/// Explicit tool calls the AI can project back down into the TENA actors.
pub(all) enum CapsuleDirective {
  /// Adjust WASM FST filter dynamically
  ZoomAttention(String, String, String) // cluster, node, intent
  /// Intervene through a Pi Zero HID mule
  EmitHid(String, Array[String]) // node, key sequence
  /// Route a media feed through the mesh proxy
  RouteStream(String, String, String) // source, proxy, output
} derive(Debug, Eq)

///|
/// Encode the directive into the native outbox.
pub fn CapsuleDirective::encode(self : CapsuleDirective) -> String {
  match self {
    ZoomAttention(cluster, node, intent) => 
      "{\"cmd\": \"zoom\", \"cluster\": \"" + cluster + "\", \"node\": \"" + node + "\", \"intent\": \"" + intent + "\"}"
    EmitHid(node, keys) => {
      // Simplistic join for mockup purposes
      let mut seq = "["
      let mut first = true
      for k in keys {
        if not(first) { seq = seq + ", " }
        seq = seq + "\"" + k + "\""
        first = false
      }
      seq = seq + "]"
      "{\"cmd\": \"hid\", \"node\": \"" + node + "\", \"sequence\": " + seq + "}"
    }
    RouteStream(source, proxy, output) => 
      "{\"cmd\": \"route\", \"source\": \"" + source + "\", \"proxy\": \"" + proxy + "\", \"out\": \"" + output + "\"}"
  }
}
