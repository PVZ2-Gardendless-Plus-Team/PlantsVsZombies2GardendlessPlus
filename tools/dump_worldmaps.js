#!/usr/bin/env node
// Dump PVZGE's world maps from the running game, for tools/extract_worldmaps.py.
//
// The island maps are Cocos prefabs: hundreds of DragonBones displays placed
// by hand, plus a WorldMap component that says which island holds which
// level, where each path goes and how far each background layer drifts.
// Decoding that from the compiled prefab format means re-implementing Cocos's
// deserializer, so this asks Cocos instead: it opens the game in a headless
// browser, instantiates each prefab and walks the result.
//
//     node tools/dump_worldmaps.js <out dir> [game url]
//
// The URL defaults to https://play.pvzge.com/. A local copy of the build
// (pvzge_web's docs/, or a desktop build unpacked by extract_desktop.py)
// served with `python3 -m http.server` works the same.
//
// Writes <out>/layouts.json (the node trees, WorldmapFeatures and the level
// node prefabs) and <out>/rigs/<skeleton uuid>.json (each DragonBones export
// the maps use, with its atlas and the uuid of the atlas image). The images
// themselves are not fetched: the web build serves AVIF, so extract_worldmaps.py
// takes the PNGs from a desktop build's native/ folder instead.
//
// Needs Playwright (preinstalled in the cloud sessions; `npm i playwright`).

const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const MAPS = ['WorldmapChooser', 'Egypt', 'Pirate', 'Cowboy', 'Future', 'Dark',
  'Beach', 'Iceage', 'LostCity', 'Epic', 'Eighties', 'Dino', 'Modern', 'Kongfu', 'Sky'];

async function main() {
  const out = process.argv[2];
  const url = process.argv[3] || 'https://play.pvzge.com/';
  if (!out) {
    console.log('usage: node tools/dump_worldmaps.js <out dir> [game url]');
    process.exit(2);
  }
  fs.mkdirSync(path.join(out, 'rigs'), { recursive: true });
  const browser = await chromium.launch({ args: ['--use-gl=swiftshader', '--ignore-gpu-blocklist'] });
  const page = await browser.newPage({ viewport: { width: 1024, height: 640 } });
  await page.goto(url, { timeout: 180000 });
  await page.waitForFunction(() => window.cc && cc.director && cc.director.getScene(),
    null, { timeout: 300000 });
  // The resources bundle loads after the first scene.
  await page.waitForFunction(() => cc.resources && cc.resources.load, null, { timeout: 120000 });

  const wanted = MAPS.map((m) => 'worldmaps/' + m + 'WORLDMAP');
  const result = await page.evaluate(async (wanted) => {
    const cls = (o) => cc.js.getClassName(o);
    const load = (p, type) => new Promise((res) =>
      cc.resources.load(p, type, (e, a) => res(e ? { error: String(e) } : a)));
    const rigs = {};

    function pathOf(n) {
      const parts = [];
      while (n && n.parent) { parts.unshift(n.name); n = n.parent; }
      return parts.join('/');
    }
    // Component fields, with nodes as paths and assets as names.
    function ser(v, depth) {
      if (v == null || typeof v !== 'object') return v;
      const c = cls(v);
      if (c === 'cc.Node') return { node: pathOf(v) };
      if (v.node && v.uuid !== undefined && cls(v.node) === 'cc.Node')
        return { component: c, node: pathOf(v.node) };
      if (v._uuid !== undefined && v.nativeUrl !== undefined) return { asset: v.name, type: c };
      if (c === 'cc.Vec3' || c === 'cc.Vec2') return [v.x, v.y];
      if (c === 'cc.Color') return [v.r, v.g, v.b, v.a];
      if (depth > 3) return null;
      if (Array.isArray(v)) return v.map((x) => ser(x, depth + 1));
      const o = {};
      for (const k of Object.keys(v)) {
        if (k.startsWith('__')) continue;
        try { o[k] = ser(v[k], depth + 1); } catch (e) { /* getter threw */ }
      }
      return o;
    }
    function rig(c) {
      const ske = c.dragonAsset, atlas = c.dragonAtlasAsset;
      if (!ske || !atlas) return null;
      const id = ske._uuid;
      if (!rigs[id]) {
        const tex = atlas.texture || atlas._texture;
        const image = tex && tex.image && tex.image.nativeUrl || '';
        rigs[id] = {
          uuid: id, atlas_uuid: atlas._uuid,
          skeleton: ske.dragonBonesJson, atlas: atlas.atlasJson,
          // native/<xx>/<uuid>.<ext>
          texture: (image.split('/').pop() || '').split('.')[0],
        };
      }
      return id;
    }
    function comp(c) {
      const type = cls(c);
      const o = { type };
      if (type === 'dragonBones.ArmatureDisplay') {
        Object.assign(o, { rig: rig(c), armature: c.armatureName, animation: c.animationName,
          play_times: c.playTimes, time_scale: c.timeScale,
          color: c.color ? [c.color.r, c.color.g, c.color.b, c.color.a] : null });
      } else if (type === 'cc.Sprite') {
        Object.assign(o, { frame: c.spriteFrame && c.spriteFrame.name,
          color: [c.color.r, c.color.g, c.color.b, c.color.a] });
      } else if (type === 'cc.Label') {
        Object.assign(o, { string: c.string, font_size: c.fontSize, font: c.font && c.font.name,
          color: [c.color.r, c.color.g, c.color.b, c.color.a] });
      } else if (type === 'cc.UITransform') {
        Object.assign(o, { size: [c.width, c.height], anchor: [c.anchorX, c.anchorY] });
      } else if (type === 'cc.UIOpacity') {
        o.opacity = c.opacity;
      } else if (!type.startsWith('cc.')) {
        const fields = {};
        for (const k of Object.keys(c)) {
          if (k.startsWith('_') || ['node', 'uuid', 'name', 'enabledInHierarchy', 'hideFlags'].includes(k)) continue;
          try { fields[k] = ser(c[k], 0); } catch (e) { /* getter threw */ }
        }
        o.fields = fields;
      }
      return o;
    }
    function walk(n) {
      return { name: n.name, active: n.active, pos: [n.position.x, n.position.y],
        scale: [n.scale.x, n.scale.y], angle: n.angle,
        comps: n.components.map(comp), children: n.children.map(walk) };
    }

    const layouts = {};
    for (const name of wanted) {
      const a = await load(name, cc.Prefab);
      layouts[name] = a.error ? a : walk(cc.instantiate(a));
    }
    // The level node, path, gift box, portal and Zomboss head prefabs hang
    // off one resource prefab rather than having names of their own.
    const rp = await load('resouce_prefabs/LevelNodesRP', cc.Prefab);
    const nodes = {};
    if (!rp.error) {
      const inst = cc.instantiate(rp);
      for (const c of inst.components)
        for (const k of Object.keys(c))
          if (c[k] && cls(c[k]) === 'cc.Prefab') nodes[k] = walk(cc.instantiate(c[k]));
    }
    const features = await load('json/Features/WorldmapFeatures', cc.JsonAsset);
    return { layouts, nodes, features: features.json || null, rigs };
  }, wanted);

  const { rigs } = result;
  delete result.rigs;
  fs.writeFileSync(path.join(out, 'layouts.json'), JSON.stringify(result));
  for (const id of Object.keys(rigs))
    fs.writeFileSync(path.join(out, 'rigs', id + '.json'), JSON.stringify(rigs[id]));
  console.log('%d maps, %d level node prefabs, %d rigs -> %s',
    Object.keys(result.layouts).length, Object.keys(result.nodes).length,
    Object.keys(rigs).length, out);
  await browser.close();
}

main().catch((e) => { console.error(e); process.exit(1); });
