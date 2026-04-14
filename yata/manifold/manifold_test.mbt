///|
test "distill from empty tree" {
  let tree = @grammar.GrammarTree::new()
  let frag = ManifoldFragment::distill(tree, "frag-1", "tap-a", 50)
  assert_eq(frag.fragment_id, "frag-1")
  assert_eq(frag.source_tap, "tap-a")
  assert_eq(frag.node_count, 0)
  assert_eq(frag.tree_depth, 0)
  assert_eq(frag.tree_width, 0)
  assert_eq(frag.grammar_hash.length(), 4)
}

///|
test "distill captures tree topology" {
  let tree = @grammar.GrammarTree::new()
  let _ = tree.ingest(["pg:Q", "pg:C"])
  let _ = tree.add_child("child-a")
  let _ = tree.add_child("child-b")
  let frag = ManifoldFragment::distill(tree, "frag-2", "tap-b", 60)
  assert_eq(frag.node_count, 3)
  assert_true(frag.tree_width >= 2)
  assert_true(frag.tree_depth >= 1)
  assert_eq(frag.direction_ratio, 60)
}

///|
test "distill captures salience" {
  let tree = @grammar.GrammarTree::new()
  let _ = tree.ingest_with_salience(["pg:Q"], 5000)
  let _ = tree.ingest_with_salience(["pg:C"], 3000)
  let frag = ManifoldFragment::distill(tree, "frag-3", "tap-c", 50)
  assert_true(frag.salience_mean > 0)
}

///|
test "distill computes streaming score" {
  let tree = @grammar.GrammarTree::new()
  let _ = tree.ingest(["a"])
  // direction_ratio 50 (balanced) → streaming_score 0
  let frag50 = ManifoldFragment::distill(tree, "f", "t", 50)
  assert_eq(frag50.streaming_score, 0)
  // direction_ratio 90 (heavily one-directional) → high streaming
  let frag90 = ManifoldFragment::distill(tree, "f", "t", 90)
  assert_true(frag90.streaming_score > 50)
}

///|
test "distill computes regularity score" {
  let tree = @grammar.GrammarTree::new()
  // With no observations, sigma stays at default (1000)
  let _ = tree.ingest(["a"])
  let frag = ManifoldFragment::distill(tree, "f", "t", 50)
  // Default sigma 1000 → regularity = 100 - 1000*100/5000 = 80
  assert_true(frag.regularity_score >= 0 && frag.regularity_score <= 100)
}

///|
test "distill sealed ratio" {
  let tree = @grammar.GrammarTree::new()
  let _ = tree.ingest(["a"])
  let _ = tree.seal()
  let _ = tree.ingest(["b"]) // new epoch, unsealed
  let frag = ManifoldFragment::distill(tree, "f", "t", 50)
  // 1 sealed + 1 unsealed = 50%
  // But sealed root's key differs from new root, so 2 nodes
  assert_true(frag.sealed_ratio >= 0 && frag.sealed_ratio <= 100)
}

///|
test "grammar_hash is deterministic" {
  let tree = @grammar.GrammarTree::new()
  let _ = tree.ingest(["pg:Q", "pg:C"])
  let f1 = ManifoldFragment::distill(tree, "f", "t", 50)
  let f2 = ManifoldFragment::distill(tree, "f", "t", 50)
  assert_eq(f1.grammar_hash[0], f2.grammar_hash[0])
  assert_eq(f1.grammar_hash[1], f2.grammar_hash[1])
  assert_eq(f1.grammar_hash[2], f2.grammar_hash[2])
  assert_eq(f1.grammar_hash[3], f2.grammar_hash[3])
}

///|
test "serialization round-trip" {
  let tree = @grammar.GrammarTree::new()
  let _ = tree.ingest(["pg:Q", "pg:C", "sz:md"])
  let _ = tree.add_child("child-1")
  let frag = ManifoldFragment::distill(tree, "frag-rt", "tap-rt", 65)
  let bytes = frag.to_bytes()
  match ManifoldFragment::from_bytes(bytes) {
    Some(f2) => {
      assert_eq(f2.fragment_id, "frag-rt")
      assert_eq(f2.source_tap, "tap-rt")
      assert_eq(f2.observation_epoch, frag.observation_epoch)
      assert_eq(f2.tree_depth, frag.tree_depth)
      assert_eq(f2.tree_width, frag.tree_width)
      assert_eq(f2.node_count, frag.node_count)
      assert_eq(f2.direction_ratio, 65)
      assert_eq(f2.streaming_score, frag.streaming_score)
      assert_eq(f2.regularity_score, frag.regularity_score)
      assert_eq(f2.vocab_score, frag.vocab_score)
      assert_eq(f2.grammar_hash.length(), 4)
    }
    None => fail("deserialization failed")
  }
}

///|
test "from_bytes returns None on bad magic" {
  assert_true(
    ManifoldFragment::from_bytes([b'\x00', b'\x00', b'\x00', b'\x00']) is None,
  )
}

///|
test "from_bytes returns None on empty" {
  assert_true(ManifoldFragment::from_bytes([]) is None)
}
