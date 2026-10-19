// The system bars over a raw screen, which the raw screen leaves empty: frame.html and creative.html draw them with
// window.drawSystemBars(svg, device, platform), where `device` is the STORE_DEVICE of the device.js that
// render_screens.dart writes and `platform` is ios or android. The SVG takes the logical size of the device as its
// viewBox, so every length below is in points (iOS) or density-independent pixels (Android).
window.drawSystemBars = (svg, device, platform) => {
  svg.setAttribute("viewBox", `0 0 ${device.width} ${device.height}`);

  // Adds an SVG element with the attributes of `attributes` to the bars.
  function draw(name, attributes, text) {
    const node = document.createElementNS("http://www.w3.org/2000/svg", name);
    for (const [key, value] of Object.entries(attributes))
      node.setAttribute(key, value);
    if (text) node.textContent = text;
    svg.append(node);
  }

  // An arc of radius `r` around the point (x, y), `angle` degrees to each side of straight up.
  function arc(x, y, r, angle) {
    const dx = r * Math.sin((angle * Math.PI) / 180);
    const dy = r * Math.cos((angle * Math.PI) / 180);
    return `M ${x - dx} ${y - dy} A ${r} ${r} 0 0 1 ${x + dx} ${y - dy}`;
  }

  // The iOS status bar of an iPhone screenshot, in points. The sizes and the positions were measured on an iPhone 16
  // Pro screenshot of the app: every item is centered at 53% of the top inset, and the time and the icons are
  // centered in the space beside the Dynamic Island, 5 points out from its middle. A screenshot shows neither the
  // Dynamic Island nor the home indicator, so the frame draws neither.
  function drawIos() {
    const { width, top } = device;
    const y = top * 0.53;
    const side = (width - 126) / 4 + 5;
    draw(
      "text",
      {
        x: side,
        y,
        "text-anchor": "middle",
        "dominant-baseline": "central",
        "font-family": '-apple-system, "SF Pro Text", system-ui, sans-serif',
        "font-size": 17,
        "font-weight": 600,
      },
      "9:41",
    );
    // Signal, Wi-Fi, and battery, 80.5 points from the left of the signal to the end of the battery cap.
    const x = width - side - 40.25;
    [4.6, 6.7, 8.8, 10.9].forEach((height, index) =>
      draw("rect", {
        x: x + index * 5,
        y: y + 5.45 - height,
        width: 3.4,
        height,
        rx: 1,
      }),
    );
    const wifi = x + 35;
    for (const r of [12.2, 7.4]) {
      draw("path", {
        d: arc(wifi, y + 6.25, r, 42),
        fill: "none",
        stroke: "#000",
        "stroke-width": 2.6,
        "stroke-linecap": "round",
      });
    }
    draw("path", {
      d: `M ${wifi} ${y + 6.25} L ${arc(wifi, y + 6.25, 3.6, 42).slice(2)} Z`,
    });
    const battery = x + 51.2;
    draw("rect", {
      x: battery,
      y: y - 6.55,
      width: 27.5,
      height: 13.1,
      rx: 4.2,
      "fill-opacity": 0.35,
    });
    draw("rect", {
      x: battery + 2,
      y: y - 4.55,
      width: 23.5,
      height: 9.1,
      rx: 2.5,
    });
    draw("rect", {
      x: battery + 28.5,
      y: y - 2.3,
      width: 1.6,
      height: 4.6,
      rx: 0.8,
      "fill-opacity": 0.4,
    });
  }

  // The Android status bar and gesture navigation bar, in density-independent pixels. The sizes and the positions
  // were measured on a Pixel 10 emulator screenshot: every status item is centered at half of the top inset, the
  // time starts 17 dp from the left, the battery cap ends 28.6 dp from the right, and the handle is centered in the
  // bottom inset.
  function drawAndroid() {
    const { width, height, top, bottom } = device;
    const ink = "#1f1f1f";
    const y = top / 2;
    draw(
      "text",
      {
        x: 17,
        y,
        "dominant-baseline": "central",
        "font-family": "Roboto, sans-serif",
        "font-size": 14.5,
        "font-weight": 500,
        fill: ink,
      },
      "9:41",
    );
    // The battery: a 24 x 13 dp body and its cap, 26.7 dp in all.
    const battery = width - 28.6 - 26.7;
    draw("rect", {
      x: battery,
      y: y - 6.5,
      width: 24,
      height: 13,
      rx: 4,
      fill: ink,
    });
    draw("rect", {
      x: battery + 25.2,
      y: y - 3.05,
      width: 1.5,
      height: 6.1,
      rx: 0.7,
      fill: ink,
    });
    // The signal: four bars in 17.1 x 12.2 dp.
    const signal = battery - 6 - 17.1;
    [0.4, 0.6, 0.8, 1].forEach((share, index) => {
      const barHeight = 12.2 * share;
      draw("rect", {
        x: signal + index * 4.6,
        y: y + 6.1 - barHeight,
        width: 3.3,
        height: barHeight,
        rx: 1,
        fill: ink,
      });
    });
    // The Wi-Fi fan: 16.4 x 12.2 dp with rounded corners.
    const wifi = signal - 5 - 8.2;
    draw("path", {
      d: `M ${wifi} ${y + 6.1} L ${arc(wifi, y + 6.1, 11.6, 45).slice(2)} Z`,
      fill: ink,
      stroke: ink,
      "stroke-width": 1.2,
      "stroke-linejoin": "round",
    });
    // The gesture handle: 108 x 3.8 dp.
    draw("rect", {
      x: width / 2 - 54,
      y: height - bottom / 2 - 1.9,
      width: 108,
      height: 3.8,
      rx: 1.9,
      fill: ink,
      "fill-opacity": 0.85,
    });
  }

  const drawers = { ios: drawIos, android: drawAndroid };
  if (!drawers[platform])
    throw new Error(`No system bars for the platform ${platform}`);
  drawers[platform]();
};
