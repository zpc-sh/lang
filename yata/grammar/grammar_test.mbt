///|
test "new grammar tree is empty" {
  let t = GrammarTree::new()
  assert_eq(t.node_count(), 0)
  assert_eq(t.current_epoch(), 0)
  assert_eq(t.total_tokens, 0)
  assert_true(t.active_root_key() is None)
}

///|
test "ingest creates root and adds tokens" {
  let t = GrammarTree::new()
  let root = t.ingest(["pg:Q", "dir:c2s", "sz:sm"])
  assert_eq(t.node_count(), 1)
  assert_eq(t.total_tokens, 3)
  match t.get_node(root) {
    Some(node) => {
      assert_eq(node.mass, 1)
      assert_eq(node.heat, 1)
      assert_true(node.maybe_routes("pg:Q"))
      assert_true(node.maybe_routes("dir:c2s"))
      assert_true(node.maybe_routes("sz:sm"))
      assert_true(node.state == Dirty)
    }
    None => fail("root node not found")
  }
}

///|
test "ingest accumulates mass on repeated calls" {
  let t = GrammarTree::new()
  let _ = t.ingest(["pg:Q"])
  let _ = t.ingest(["pg:C"])
  let _ = t.ingest(["pg:Q"])
  match t.get_node(t.active_root_key().unwrap()) {
    Some(node) => {
      assert_eq(node.mass, 3)
      assert_true(node.maybe_routes("pg:Q"))
      assert_true(node.maybe_routes("pg:C"))
    }
    None => fail("root not found")
  }
}

///|
test "seal freezes epoch and merges blooms" {
  let t = GrammarTree::new()
  let _ = t.ingest(["pg:Q", "pg:C"])
  let sealed_key = t.seal()
  assert_true(sealed_key is Some(_))
  assert_eq(t.current_epoch(), 1)
  assert_true(t.hot_root is None)
  match t.get_node(sealed_key.unwrap()) {
    Some(node) => assert_true(node.state == Sealed)
    None => fail("sealed node not found")
  }
}

///|
test "seal on empty tree returns None" {
  let t = GrammarTree::new()
  assert_true(t.seal() is None)
  assert_eq(t.current_epoch(), 0)
}

///|
test "add_child creates parent-child edge" {
  let t = GrammarTree::new()
  let _ = t.ingest(["pg:Q"])
  assert_true(t.add_child("child-1"))
  assert_eq(t.node_count(), 2)
  match t.get_node(t.active_root_key().unwrap()) {
    Some(root) => assert_eq(root.children.length(), 1)
    None => fail("root not found")
  }
}

///|
test "seal merges child blooms upward" {
  let t = GrammarTree::new()
  let _ = t.ingest(["root-token"])
  let _ = t.add_child("child-1")
  match t.get_node("child-1") {
    Some(child) => {
      let updated = child.ingest_tokens(["child-only-token"])
      t.nodes["child-1"] = updated
    }
    None => fail("child not found")
  }
  let sealed_key = t.seal().unwrap()
  match t.get_node(sealed_key) {
    Some(root) => {
      assert_true(root.maybe_routes("root-token"))
      assert_true(root.maybe_routes("child-only-token"))
    }
    None => fail("sealed root not found")
  }
}

///|
test "sparse projection filters by token" {
  let t = GrammarTree::new()
  let _ = t.ingest(["pg:Q", "pg:C"])
  let _ = t.add_child("child-pg")
  match t.get_node("child-pg") {
    Some(child) => t.nodes["child-pg"] = child.ingest_tokens(["pg:Q"])
    None => fail("child not found")
  }
  let _ = t.add_child("child-http")
  match t.get_node("child-http") {
    Some(child) => t.nodes["child-http"] = child.ingest_tokens(["http:GET"])
    None => fail("child not found")
  }
  let sparse = t.sparse(["pg:Q"])
  assert_true(sparse.has_node(t.active_root_key().unwrap()))
  assert_true(sparse.has_node("child-pg"))
}

///|
test "sparse with empty tokens returns all nodes" {
  let t = GrammarTree::new()
  let _ = t.ingest(["a"])
  let _ = t.add_child("c1")
  let sparse = t.sparse([])
  assert_eq(sparse.node_count(), t.node_count())
}

///|
test "diff detects additions and removals" {
  let t1 = GrammarTree::new()
  let _ = t1.ingest(["pg:Q"])
  let t2 = GrammarTree::new()
  let _ = t2.ingest(["pg:Q"])
  let _ = t2.add_child("new-child")
  let d = t1.diff(t2)
  assert_eq(d.added.length(), 1)
  assert_eq(d.added[0], "new-child")
}

///|
test "diff detects changes" {
  let t1 = GrammarTree::new()
  let _ = t1.ingest(["pg:Q"])
  let t2 = GrammarTree::new()
  let _ = t2.ingest(["pg:Q"])
  let _ = t2.ingest(["pg:C"])
  let d = t1.diff(t2)
  assert_eq(d.changed.length(), 1)
}

///|
test "diff of identical trees" {
  let t1 = GrammarTree::new()
  let _ = t1.ingest(["pg:Q"])
  let t2 = GrammarTree::new()
  let _ = t2.ingest(["pg:Q"])
  let d = t1.diff(t2)
  assert_true(d.is_empty())
  assert_eq(d.unchanged, 1)
}

///|
test "merge combines two trees" {
  let t1 = GrammarTree::new()
  let _ = t1.ingest(["pg:Q"])
  let t2 = GrammarTree::new()
  let _ = t2.ingest(["pg:C"])
  let _ = t2.add_child("t2-child")
  match t2.get_node("t2-child") {
    Some(child) => t2.nodes["t2-child"] = child.ingest_tokens(["pg:Z"])
    None => ()
  }
  let merged = t1.merge(t2)
  assert_true(merged.node_count() >= 2)
  match merged.get_node(merged.active_root_key().unwrap()) {
    Some(root) => {
      assert_true(root.maybe_routes("pg:Q"))
      assert_true(root.maybe_routes("pg:C"))
    }
    None => fail("merged root not found")
  }
  assert_true(merged.get_node("t2-child") is Some(_))
}

///|
test "similarity: identical trees score 100" {
  let t1 = GrammarTree::new()
  let _ = t1.ingest(["pg:Q", "pg:C", "pg:Z"])
  let t2 = GrammarTree::new()
  let _ = t2.ingest(["pg:Q", "pg:C", "pg:Z"])
  assert_eq(t1.similarity(t2), 100)
}

///|
test "similarity: empty trees score 100" {
  let t1 = GrammarTree::new()
  let t2 = GrammarTree::new()
  assert_eq(t1.similarity(t2), 100)
}

///|
test "similarity: disjoint trees score low" {
  let t1 = GrammarTree::new()
  let _ = t1.ingest(["pg:Q", "pg:C"])
  let t2 = GrammarTree::new()
  let _ = t2.ingest(["http:GET", "http:POST"])
  let score = t1.similarity(t2)
  assert_true(score < 50)
}

///|
test "gaussian pair starts uninformative" {
  let g = GaussianPair::new()
  assert_eq(g.mu, 0)
  assert_eq(g.sigma, 1000)
  assert_eq(g.n, 0)
}

///|
test "gaussian pair updates with welford" {
  let mut g = GaussianPair::new()
  g = g.update(5000)
  assert_eq(g.n, 1)
  assert_eq(g.mu, 5000)
  g = g.update(3000)
  assert_eq(g.n, 2)
  assert_eq(g.mu, 4000)
}

///|
test "gaussian should_execute" {
  let g : GaussianPair = { mu: 5000, sigma: 1000, n: 10 }
  assert_true(g.should_execute(1000, 3000))
  assert_true(!g.should_execute(2000, 4000))
}

///|
test "gaussian merge combines observations" {
  let g1 : GaussianPair = { mu: 4000, sigma: 500, n: 10 }
  let g2 : GaussianPair = { mu: 6000, sigma: 800, n: 5 }
  let merged = g1.merge(g2)
  assert_eq(merged.n, 15)
  assert_true(merged.mu > 4000 && merged.mu < 6000)
}

///|
test "bloom add and maybe_contains" {
  let b = GrammarBloom::new()
  b.add("pg:Q")
  b.add("pg:C")
  assert_true(b.maybe_contains("pg:Q"))
  assert_true(b.maybe_contains("pg:C"))
}

///|
test "bloom merge ORs bits" {
  let b1 = GrammarBloom::new()
  b1.add("pg:Q")
  let b2 = GrammarBloom::new()
  b2.add("http:GET")
  let merged = b1.merge(b2)
  assert_true(merged.maybe_contains("pg:Q"))
  assert_true(merged.maybe_contains("http:GET"))
}

///|
test "bloom popcount and overlap" {
  let b1 = GrammarBloom::new()
  b1.add("a")
  let pop1 = b1.popcount()
  assert_true(pop1 > 0)
  assert_true(pop1 <= 3)
  let b2 = GrammarBloom::new()
  b2.add("a")
  assert_eq(b1.overlap(b2), pop1)
}

///|
test "ingest_with_salience updates timing" {
  let t = GrammarTree::new()
  let _ = t.ingest_with_salience(["pg:Q"], 5000)
  let _ = t.ingest_with_salience(["pg:C"], 3000)
  match t.get_node(t.active_root_key().unwrap()) {
    Some(root) => {
      assert_eq(root.salience.n, 2)
      assert_true(root.salience.mu > 0)
    }
    None => fail("root not found")
  }
}

///|
test "serialization round-trip" {
  let t = GrammarTree::new()
  let _ = t.ingest(["pg:Q", "pg:C", "sz:md"])
  let _ = t.ingest(["pg:P", "pg:1"])
  let _ = t.add_child("child-a")
  match t.get_node("child-a") {
    Some(child) => t.nodes["child-a"] = child.ingest_tokens(["pg:Z"])
    None => ()
  }
  let _ = t.ingest_with_salience(["pg:Q"], 4200)
  let bytes = t.to_bytes()
  match GrammarTree::from_bytes(bytes) {
    Some(t2) => {
      assert_eq(t2.node_count(), t.node_count())
      assert_eq(t2.epoch, t.epoch)
      assert_eq(t2.total_tokens, t.total_tokens)
      match t2.get_node(t2.active_root_key().unwrap()) {
        Some(root) => {
          assert_true(root.maybe_routes("pg:Q"))
          assert_true(root.maybe_routes("pg:C"))
          assert_eq(root.mass, 3)
        }
        None => fail("deserialized root not found")
      }
      assert_true(t2.get_node("child-a") is Some(_))
    }
    None => fail("deserialization failed")
  }
}

///|
test "from_bytes returns None on bad magic" {
  let data : Array[Byte] = [b'\x00', b'\x00', b'\x00', b'\x00']
  assert_true(GrammarTree::from_bytes(data) is None)
}

///|
test "from_bytes returns None on empty" {
  assert_true(GrammarTree::from_bytes([]) is None)
}

///|
test "total_mass sums across nodes" {
  let t = GrammarTree::new()
  let _ = t.ingest(["a"])
  let _ = t.ingest(["b"])
  let _ = t.add_child("c")
  match t.get_node("c") {
    Some(child) => t.nodes["c"] = child.ingest_tokens(["x"])
    None => ()
  }
  assert_eq(t.total_mass(), 3)
}

///|
test "multiple seal epochs" {
  let t = GrammarTree::new()
  let _ = t.ingest(["epoch-1"])
  let _ = t.seal()
  assert_eq(t.current_epoch(), 1)
  let _ = t.ingest(["epoch-2"])
  let _ = t.seal()
  assert_eq(t.current_epoch(), 2)
}
