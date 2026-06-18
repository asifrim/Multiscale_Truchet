// ============================================================
//  Palettes.pde — colour-palette management
//
//  Palettes are sourced from COLOURlovers' all-time most-loved list:
//  https://www.colourlovers.com/palettes/new/all-time/meta
//
//  Two classes:
//    Palette         — a named, ordered set of colours.
//    PaletteManager  — a collection of palettes with selection helpers.
//
//  The manager ships seeded with a curated snapshot of the all-time top
//  palettes (their hex values are stable and widely reproduced). It can
//  also refresh live from the COLOURlovers JSON API via
//  loadFromColourLovers(); note that COLOURlovers sits behind a Cloudflare
//  challenge, so the live call is best-effort and silently falls back to
//  the built-in set when the network blocks it.
//
//  Usage:
//    PaletteManager palettes;          // global
//    palettes = new PaletteManager();  // in setup()
//    palettes.tryLoadLive(20);         // optional: refresh from the web
//    ...
//    Palette p = palettes.current();
//    color bg = p.lightest();
//    color fg = p.darkest();
//    color c  = p.get(i);              // i wraps around the palette
//    palettes.next();  palettes.prev();  palettes.randomPalette();
//    color rc = p.randomColor();       // a random swatch from the palette
// ============================================================

// ---- a single palette ------------------------------------------
class Palette {
  String  title;
  String  author;     // COLOURlovers user, "" if unknown
  int     id;         // COLOURlovers palette id, 0 if unknown
  color[] colors;

  Palette(String title, color[] colors) {
    this.title  = title;
    this.author = "";
    this.id     = 0;
    this.colors = colors;
  }

  int size() { return colors.length; }

  // Cycle the colour order one step (colors[0] moves to the end). Changes which
  // colours map where in order-sensitive schemes (e.g. the gradient scheme).
  void rotate() {
    if (colors.length < 2) return;
    color first = colors[0];
    for (int i = 0; i < colors.length - 1; i++) colors[i] = colors[i + 1];
    colors[colors.length - 1] = first;
  }

  // Indexed access that wraps, so callers can ask for any index safely.
  color get(int i) {
    int n = colors.length;
    if (n == 0) return color(0);
    return colors[((i % n) + n) % n];
  }

  color randomColor() { return colors[int(random(colors.length))]; }

  // Perceptual-ish luminance (Rec. 601) used to find extremes.
  float lum(color c) {
    return 0.299 * red(c) + 0.587 * green(c) + 0.114 * blue(c);
  }

  color darkest() {
    color best = colors[0]; float lo = lum(best);
    for (color c : colors) { float l = lum(c); if (l < lo) { lo = l; best = c; } }
    return best;
  }

  color lightest() {
    color best = colors[0]; float hi = lum(best);
    for (color c : colors) { float l = lum(c); if (l > hi) { hi = l; best = c; } }
    return best;
  }

  // COLOURlovers attribution URL (valid only when id is known).
  String url() {
    return id > 0 ? "https://www.colourlovers.com/palette/" + id : "";
  }

  String toString() {
    return title + " (" + colors.length + " colours" +
           (author.length() > 0 ? ", by " + author : "") + ")";
  }
}

// ---- the manager -----------------------------------------------
class PaletteManager {
  ArrayList<Palette> palettes = new ArrayList<Palette>();
  int current = 0;

  PaletteManager() { loadDefaults(); }

  // --- collection access ---
  int count() { return palettes.size(); }

  Palette get(int i) {
    int n = palettes.size();
    return palettes.get(((i % n) + n) % n);
  }

  Palette current() { return palettes.get(current); }

  void setCurrent(int i) {
    int n = palettes.size();
    current = ((i % n) + n) % n;
  }

  Palette next()   { setCurrent(current + 1); return current(); }
  Palette prev()   { setCurrent(current - 1); return current(); }

  // Pick (and select) a random palette.
  Palette randomPalette() {
    setCurrent(int(random(palettes.size())));
    return current();
  }

  Palette byTitle(String t) {
    for (Palette p : palettes) if (p.title.equalsIgnoreCase(t)) return p;
    return null;
  }

  void add(Palette p) { if (p != null) palettes.add(p); }

  // --- building palettes from hex ---
  // Parse a COLOURlovers-style hex code ("FA6900", "#FA6900", "F90") -> color.
  color hexColor(String h) {
    if (h == null) return color(0);
    h = h.trim();
    if (h.startsWith("#")) h = h.substring(1);
    if (h.length() == 3) {                       // shorthand: F90 -> FF9900
      h = "" + h.charAt(0) + h.charAt(0)
            + h.charAt(1) + h.charAt(1)
            + h.charAt(2) + h.charAt(2);
    }
    if (h.length() != 6) return color(0);
    return unhex("FF" + h);                       // opaque ARGB
  }

  Palette fromHex(String title, String[] hexes) {
    color[] cols = new color[hexes.length];
    for (int i = 0; i < hexes.length; i++) cols[i] = hexColor(hexes[i]);
    return new Palette(title, cols);
  }

  // --- live refresh from COLOURlovers (best-effort) ---------------
  // Returns true if it fetched and replaced the set, false on any failure
  // (Cloudflare block, no network, malformed JSON) — leaving the built-ins
  // intact. orderCol "" => all-time top; numResults capped by the API at 100.
  boolean tryLoadLive(int numResults) {
    return loadFromColourLovers("", numResults);
  }

  boolean loadFromColourLovers(String orderCol, int numResults) {
    String url = "https://www.colourlovers.com/api/palettes/top?format=json"
               + "&numResults=" + numResults
               + (orderCol.length() > 0 ? "&orderCol=" + orderCol : "");
    try {
      JSONArray arr = loadJSONArray(url);
      if (arr == null || arr.size() == 0) return false;
      ArrayList<Palette> fetched = new ArrayList<Palette>();
      for (int i = 0; i < arr.size(); i++) {
        JSONObject o = arr.getJSONObject(i);
        JSONArray cols = o.getJSONArray("colors");
        if (cols == null || cols.size() == 0) continue;
        String[] hex = new String[cols.size()];
        for (int k = 0; k < cols.size(); k++) hex[k] = cols.getString(k);
        Palette p = fromHex(o.getString("title", "untitled"), hex);
        p.author = o.getString("userName", "");
        p.id     = o.getInt("id", 0);
        fetched.add(p);
      }
      if (fetched.size() == 0) return false;
      palettes = fetched;
      current  = 0;
      println("PaletteManager: loaded " + palettes.size() + " palettes from COLOURlovers.");
      return true;
    } catch (Exception e) {
      println("PaletteManager: live fetch failed (" + e.getMessage()
            + "); using built-in palettes.");
      return false;
    }
  }

  // --- built-in snapshot of all-time top COLOURlovers palettes ----
  // Curated from https://www.colourlovers.com/palettes/new/all-time/meta .
  // Hex values only (the durable, reproduced data); ids/authors are left
  // for the live loader to fill in.
  void loadDefaults() {
    palettes.clear();
    add(fromHex("Giant Goldfish",   new String[]{"69D2E7","A7DBD8","E0E4CC","F38630","FA6900"}));
    add(fromHex("Thought Provoking",new String[]{"ECD078","D95B43","C02942","542437","53777A"}));
    add(fromHex("Terra",            new String[]{"E8DDCB","CDB380","036564","033649","031634"}));
    add(fromHex("Ocean Five",       new String[]{"00A0B0","6A4A3C","CC333F","EB6841","EDC951"}));
    add(fromHex("Cheer Up Emo Kid", new String[]{"556270","4ECDC4","C7F464","FF6B6B","C44D58"}));
    add(fromHex("let them eat cake",new String[]{"774F38","E08E79","F1D4AF","ECE5CE","C5E0DC"}));
    add(fromHex("Adrift in Dreams", new String[]{"CFF09E","A8DBA8","79BD9A","3B8686","0B486B"}));
    add(fromHex("curiosity killed", new String[]{"EFFFCD","DCE9BE","555152","2E2633","99173C"}));
    add(fromHex("i demand a pancake",new String[]{"594F4F","547980","45ADA8","9DE0AD","E5FCC2"}));
    add(fromHex("Vintage Modern",   new String[]{"8C2318","5E8C6A","88A65E","BFB35A","F2C45A"}));
    add(fromHex("Fresh Cut Day",    new String[]{"00A8C6","40C0CB","F9F2E7","AEE239","8FBE00"}));
    add(fromHex("Sea Side",         new String[]{"E5FCC2","9DE0AD","45ADA8","547980","594F4F"}));

    // More of the all-time most-loved list. Hex verified against two independent
    // verbatim dumps of the COLOURlovers top-100 (Experience-Monks/nice-color-
    // palettes + federico-pepe/nice-color-palettes, which agree hex-for-hex);
    // emoji/letter-spaced titles in the source were skipped.
    add(fromHex("Compatible",          new String[]{"3FB8AF","7FC7AF","DAD8A7","FF9E9D","FF3D7F"}));
    add(fromHex("LoversInJapan",       new String[]{"E94E77","D68189","C6A49A","C6E5D9","F4EAD5"}));
    add(fromHex("Good Friends",        new String[]{"D9CEB2","948C75","D5DED9","7A6A53","99B2B7"}));
    add(fromHex("dream magnet",        new String[]{"343838","005F6B","008C9E","00B4CC","00DFFC"}));
    add(fromHex("clairedelune",        new String[]{"413E4A","73626E","B38184","F0B49E","F7E4BE"}));
    add(fromHex("coup de grace",       new String[]{"99B898","FECEA8","FF847C","E84A5F","2A363B"}));
    add(fromHex("Dance To Forget",     new String[]{"FF4E50","FC913A","F9D423","EDE574","E1F5C4"}));
    add(fromHex("mystery machine",     new String[]{"554236","F77825","D3CE3D","F1EFA5","60B99A"}));
    add(fromHex("you are beautiful",   new String[]{"351330","424254","64908A","E8CAA4","CC2A41"}));
    add(fromHex("Wasabi Suicide",      new String[]{"FF4242","F4FAD2","D4EE5E","E1EDB9","F0F2EB"}));
    add(fromHex("Headache",            new String[]{"655643","80BCA3","F6F7BD","E6AC27","BF4D28"}));
    add(fromHex("Maddening Caravan",   new String[]{"FAD089","FF9C5B","F5634A","ED303C","3B8183"}));
    add(fromHex("Storming Psychedelia",new String[]{"BCBDAC","CFBE27","F27435","F02475","3B2D38"}));
    add(fromHex("tech light",          new String[]{"D1E751","FFFFFF","000000","4DBCE9","26ADE4"}));
    add(fromHex("forever lost",        new String[]{"5D4157","838689","A8CABA","CAD7B2","EBE3AA"}));
    add(fromHex("Papua New Guinea",    new String[]{"5E412F","FCEBB6","78C0A8","F07818","F0A830"}));
    add(fromHex("Newly Risen Moon",    new String[]{"EEE6AB","C5BC8E","696758","45484B","36393B"}));
    add(fromHex("A Dream in Color",    new String[]{"1B676B","519548","88C425","BEF202","EAFDE6"}));
    add(fromHex("1001 Stories",        new String[]{"F8B195","F67280","C06C84","6C5B7B","355C7D"}));
    add(fromHex("Lena's Love Letter",  new String[]{"F04155","FF823A","F2F26F","FFF7BD","95CFB7"}));
    add(fromHex("Koi Carp",            new String[]{"F0D8A8","3D1C00","86B8B1","F2D694","FA2A00"}));
    add(fromHex("Hymn For My Soul",    new String[]{"2A044A","0B2E59","0D6759","7AB317","A0C55F"}));
    add(fromHex("lucky bubble gum",    new String[]{"67917A","170409","B8AF03","CCBF82","E33258"}));
    add(fromHex("Entrapped InAPalette",new String[]{"B9D7D9","668284","2A2829","493736","7B3B3B"}));
    add(fromHex("Very",                new String[]{"BBBB88","CCC68D","EEDD99","EEC290","EEAA88"}));
    add(fromHex("it's raining love",   new String[]{"A3A948","EDB92E","F85931","CE1836","009989"}));
    add(fromHex("Funny Like the Moon", new String[]{"E8D5B7","0E2430","FC3A51","F5B349","E8D5B9"}));
    add(fromHex("I like your Smile",   new String[]{"B3CC57","ECF081","FFBE40","EF746F","AB3E5B"}));
    add(fromHex("Thumbelina",          new String[]{"AB526B","BCA297","C5CEAE","F0E2A4","F4EBC3"}));
    add(fromHex("Machu Picchu",        new String[]{"607848","789048","C0D860","F0F0D8","604848"}));
    add(fromHex("Influenza",           new String[]{"300030","480048","601848","C04848","F07241"}));
    add(fromHex("The Way You Love Me", new String[]{"1C2130","028F76","B3E099","FFEAAD","D14334"}));
    add(fromHex("Miaka",               new String[]{"FC354C","29221F","13747D","0ABFBC","FCF7C5"}));
    current = 0;
  }
}
