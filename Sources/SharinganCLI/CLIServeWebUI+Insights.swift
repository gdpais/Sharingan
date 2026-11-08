import Foundation

/// The web dashboard's insight sections, injected into `html` at its `/*__INSIGHTS_STYLE__*/` and
/// `/*__INSIGHTS_SCRIPT__*/` markers. They render `snapshot.insights` below the provider cards with plain SVG and
/// no dependencies, and stay empty when a snapshot has no insights block.
extension CLIServeWebUI {
    /// Series colors copy the app's `ChartPalette` slots in order (light, then dark); Other is the neutral gray.
    static let insightsStyle = #"""
    .insights {
          --series-0: #2A78D6;
          --series-1: #EB6834;
          --series-2: #1BAF7A;
          --series-3: #EDA100;
          --series-4: #E87BA4;
          --series-5: #008300;
          --series-6: #6250D6;
          --series-7: #E34948;
          --series-other: #8E8E93;
          margin-top: 8px;
        }

        @media (prefers-color-scheme: dark) {
          .insights {
            --series-0: #3987E5;
            --series-1: #D95926;
            --series-2: #199E70;
            --series-3: #C98500;
            --series-4: #D55181;
            --series-5: #008300;
            --series-6: #9085E9;
            --series-7: #E66767;
            --series-other: #8E8E93;
          }
        }

        .insights .s0 { --c: var(--series-0); }
        .insights .s1 { --c: var(--series-1); }
        .insights .s2 { --c: var(--series-2); }
        .insights .s3 { --c: var(--series-3); }
        .insights .s4 { --c: var(--series-4); }
        .insights .s5 { --c: var(--series-5); }
        .insights .s6 { --c: var(--series-6); }
        .insights .s7 { --c: var(--series-7); }
        .insights .so { --c: var(--series-other); }

        .insights-head {
          display: flex;
          flex-wrap: wrap;
          align-items: baseline;
          justify-content: space-between;
          gap: 4px 12px;
          margin-bottom: 10px;
        }

        .insights-head .group-title {
          margin: 0;
        }

        .insights-note,
        .insight-sub,
        .insight-readout,
        .insight-legend,
        .insight-delta,
        .trend-provider,
        .trend-path,
        .trend-change {
          color: var(--muted);
          font-size: 12px;
        }

        .insight-tiles {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(min(100%, 180px), 1fr));
          gap: 10px;
          margin-bottom: 14px;
        }

        .insight-tile {
          padding: 12px 13px;
          border: 1px solid var(--line);
          border-radius: 12px;
          background: var(--surface);
          box-shadow: var(--shadow);
        }

        .insight-tile .metric-value {
          font-size: 18px;
        }

        .insight-tile .insight-spark {
          margin-top: 6px;
        }

        .insight-grid {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(min(100%, 380px), 1fr));
          gap: 14px;
          margin-bottom: 26px;
        }

        .insight-card h3 {
          margin: 0 0 2px;
          font-size: 14px;
          letter-spacing: -0.01em;
        }

        .insight-sub {
          margin: 0 0 8px;
        }

        .insight-chart {
          display: block;
          width: 100%;
          height: auto;
          overflow: visible;
        }

        .insight-chart .gridline {
          stroke: var(--line);
          stroke-width: 0.6;
        }

        .insight-chart .axis {
          fill: var(--muted);
          font-size: 8px;
        }

        .insight-chart rect.bar {
          fill: var(--c, var(--series-other));
        }

        .insight-chart .insight-mark {
          outline: none;
        }

        .insight-chart .insight-mark:hover rect,
        .insight-chart .insight-mark:focus-visible rect,
        .insight-chart rect.insight-mark:hover,
        .insight-chart rect.insight-mark:focus-visible {
          stroke: var(--text);
          stroke-width: 0.8;
        }

        .insight-chart .heat-0 { fill: color-mix(in srgb, var(--text), transparent 93%); }
        .insight-chart .heat-1 { fill: color-mix(in srgb, var(--series-0) 30%, transparent); }
        .insight-chart .heat-2 { fill: color-mix(in srgb, var(--series-0) 52%, transparent); }
        .insight-chart .heat-3 { fill: color-mix(in srgb, var(--series-0) 76%, transparent); }
        .insight-chart .heat-4 { fill: var(--series-0); }

        .insight-readout {
          min-height: 18px;
          margin-top: 6px;
          overflow-wrap: anywhere;
        }

        .insight-legend {
          display: flex;
          flex-wrap: wrap;
          gap: 4px 12px;
          margin-top: 8px;
        }

        .legend-item {
          display: inline-flex;
          align-items: center;
          gap: 5px;
          min-width: 0;
        }

        .swatch {
          flex: none;
          width: 9px;
          height: 9px;
          border-radius: 2px;
          background: var(--c, var(--series-other));
        }

        .swatch.heat-1 { background: color-mix(in srgb, var(--series-0) 30%, transparent); }
        .swatch.heat-2 { background: color-mix(in srgb, var(--series-0) 52%, transparent); }
        .swatch.heat-3 { background: color-mix(in srgb, var(--series-0) 76%, transparent); }
        .swatch.heat-4 { background: var(--series-0); }

        .insight-spark {
          display: block;
          width: 100%;
          height: 24px;
          overflow: visible;
        }

        .insight-spark polyline {
          fill: none;
          stroke: var(--c, var(--series-other));
          stroke-width: 1.5;
          stroke-linecap: round;
          stroke-linejoin: round;
          vector-effect: non-scaling-stroke;
        }

        .insight-spark circle {
          fill: var(--c, var(--series-other));
        }

        .trend-row {
          display: grid;
          grid-template-columns: 9px minmax(0, 1fr) minmax(60px, 120px) auto 52px;
          align-items: center;
          gap: 10px;
          padding: 8px 0;
          border-top: 1px solid var(--line);
        }

        .trend-row:focus-visible {
          outline: 2px solid #49a3b0;
          outline-offset: 2px;
        }

        .trend-name {
          display: grid;
          min-width: 0;
        }

        .trend-label,
        .trend-path {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }

        .trend-total,
        .trend-change {
          font-variant-numeric: tabular-nums;
          text-align: right;
          white-space: nowrap;
        }

        @media (max-width: 620px) {
          .trend-row {
            grid-template-columns: 9px minmax(0, 1fr) auto;
          }

          .trend-row .insight-spark,
          .trend-row .trend-change {
            display: none;
          }
        }
    """#

    static let insightsScript = #"""
    // Insights: charts over local cost history from `snapshot.insights`, which older servers omit.
        const insightSvgNS = "http://www.w3.org/2000/svg";
        const insightSlotCount = 8;
        const insightBox = { width: 320, height: 132, left: 40, right: 6, top: 6, bottom: 16 };

        function insightSvg(tag, attributes) {
          const element = document.createElementNS(insightSvgNS, tag);
          for (const [key, value] of Object.entries(attributes || {})) element.setAttribute(key, String(value));
          return element;
        }

        function seriesClass(rank, isOther) {
          const index = Number(rank);
          return isOther || !Number.isInteger(index) || index < 0 || index >= insightSlotCount ? "so" : `s${index}`;
        }

        // 1-2-5 ticks from zero to a nice ceiling, matching the app's ChartNiceScale.
        function niceValue(value) {
          if (!Number.isFinite(value) || !(value > 0)) return null;
          const magnitude = Math.pow(10, Math.floor(Math.log10(value)));
          const mantissa = [1, 2, 5, 10].find(candidate => candidate >= value / magnitude) ?? 10;
          const result = mantissa * magnitude;
          return Number.isFinite(result) ? result : null;
        }

        function niceTicks(maximum, targetIntervals = 4) {
          if (!Number.isFinite(maximum) || !(maximum > 0)) return [];
          const step = niceValue(maximum / targetIntervals);
          if (!step) return [];
          const intervals = Math.max(1, Math.ceil(maximum / step - 1e-9));
          const factor = Math.pow(10, Math.max(0, -Math.floor(Math.log10(step))));
          return Array.from({ length: intervals + 1 }, (_, index) => Math.round(index * step * factor) / factor);
        }

        function dayNumber(key) {
          const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(typeof key === "string" ? key : "");
          if (!match) return null;
          return Math.round(Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3])) / 86400000);
        }

        function dayLabel(key) {
          const day = dayNumber(key);
          if (day === null) return typeof key === "string" ? key : "";
          return new Intl.DateTimeFormat(undefined, { month: "short", day: "numeric", timeZone: "UTC" })
            .format(new Date(day * 86400000));
        }

        function weekdayName(weekday) {
          // 1 January 2023 was a Sunday, which is Calendar weekday 1.
          return new Intl.DateTimeFormat(undefined, { weekday: "short", timeZone: "UTC" })
            .format(new Date(Date.UTC(2023, 0, finiteNumber(weekday, 1))));
        }

        function hourText(hour) {
          return `${String(finiteNumber(hour)).padStart(2, "0")}:00`;
        }

        function percentText(fraction) {
          return new Intl.NumberFormat(undefined, { style: "percent", maximumFractionDigits: 0 })
            .format(finiteNumber(fraction));
        }

        // Whole-dollar steps drop the cents, so every label on one axis has the same precision.
        function tickDollars(value, step) {
          const digits = step < 1 ? 2 : 0;
          return new Intl.NumberFormat(undefined, {
            style: "currency",
            currency: "USD",
            minimumFractionDigits: digits,
            maximumFractionDigits: digits
          }).format(finiteNumber(value));
        }

        function signed(text, value) {
          return value > 0 ? `+${text}` : text;
        }

        function makeReadout(defaultText) {
          const element = node("div", "insight-readout", defaultText);
          element.setAttribute("aria-live", "polite");
          return {
            element,
            show(text) { element.textContent = text; },
            reset() { element.textContent = defaultText; }
          };
        }

        // Hover and keyboard focus both show a mark's detail; the SVG title keeps the native tooltip.
        function attachDetail(mark, readout, text) {
          const title = document.createElementNS(insightSvgNS, "title");
          title.textContent = text;
          mark.append(title);
          mark.setAttribute("tabindex", "0");
          mark.setAttribute("aria-label", text);
          mark.addEventListener("mouseenter", () => readout.show(text));
          mark.addEventListener("focus", () => readout.show(text));
          mark.addEventListener("mouseleave", () => readout.reset());
          mark.addEventListener("blur", () => readout.reset());
        }

        function insightLegend(items) {
          const legend = node("div", "insight-legend");
          for (const item of items) {
            const entry = node("span", "legend-item");
            const swatch = node("span", `swatch ${item.className}`);
            swatch.setAttribute("aria-hidden", "true");
            entry.append(swatch, node("span", "", item.label));
            legend.append(entry);
          }
          return legend;
        }

        function plotY(value, yMax) {
          const plotHeight = insightBox.height - insightBox.top - insightBox.bottom;
          return insightBox.top + plotHeight - (Math.max(0, value) / yMax) * plotHeight;
        }

        function chartFrame(label, ticks, formatTick) {
          const svg = insightSvg("svg", {
            viewBox: `0 0 ${insightBox.width} ${insightBox.height}`,
            role: "group",
            "aria-label": label
          });
          svg.setAttribute("class", "insight-chart");
          const yMax = ticks[ticks.length - 1];
          const step = ticks.length > 1 ? ticks[1] - ticks[0] : yMax;
          for (const tick of ticks) {
            const y = plotY(tick, yMax);
            svg.append(insightSvg("line", {
              class: "gridline",
              x1: insightBox.left,
              x2: insightBox.width - insightBox.right,
              y1: y,
              y2: y
            }));
            const text = insightSvg("text", { class: "axis", x: insightBox.left - 4, y: y + 3, "text-anchor": "end" });
            text.textContent = formatTick(tick, step);
            svg.append(text);
          }
          return svg;
        }

        function appendSlotLabels(svg, first, last) {
          const y = insightBox.height - 4;
          const start = insightSvg("text", { class: "axis", x: insightBox.left, y, "text-anchor": "start" });
          start.textContent = first;
          const right = insightBox.width - insightBox.right;
          const end = insightSvg("text", { class: "axis", x: right, y, "text-anchor": "end" });
          end.textContent = last;
          svg.append(start, end);
        }

        // Stacked bars: `columns` holds {slot, label, detail, parts: [{className, start, end}]}.
        function stackedBars(svg, columns, slotCount, yMax, readout) {
          const plotWidth = insightBox.width - insightBox.left - insightBox.right;
          const slot = plotWidth / Math.max(1, slotCount);
          const barWidth = Math.max(slot * 0.72, 0.6);
          for (const column of columns) {
            if (!(column.slot >= 0 && column.slot < slotCount)) continue;
            const x = insightBox.left + column.slot * slot + (slot - barWidth) / 2;
            const group = insightSvg("g", { class: "insight-mark" });
            for (const part of column.parts) {
              const top = plotY(part.end, yMax);
              const bottom = plotY(part.start, yMax);
              if (!(bottom - top > 0)) continue;
              group.append(insightSvg("rect", {
                class: `bar ${part.className}`,
                x,
                y: top,
                width: barWidth,
                height: Math.max(bottom - top, 0.4)
              }));
            }
            attachDetail(group, readout, column.detail);
            svg.append(group);
          }
        }

        function insightCard(title, subtitle) {
          const card = node("article", "card insight-card");
          card.append(node("h3", "", title));
          if (subtitle) card.append(node("p", "insight-sub", subtitle));
          return card;
        }

        function renderCostByModel(entry, range) {
          const models = Array.isArray(entry.models) ? entry.models : [];
          const days = Array.isArray(entry.days) ? entry.days : [];
          const start = dayNumber(range.start);
          const slotCount = Math.max(1, finiteNumber(range.days, 30));
          const maxTotal = Math.max(0, ...days.map(day => finiteNumber(day.total)));
          const ticks = niceTicks(maxTotal);
          if (start === null || !ticks.length) return null;
          const providerName = entry.providerName || entry.provider || "Provider";
          const card = insightCard(`${providerName} · cost by model`, "Daily estimated spend, top models stacked");
          const readout = makeReadout("Hover or focus a day to see its models.");
          const svg = chartFrame(`${providerName} daily spend by model`, ticks, tickDollars);
          const columns = days.map(day => {
            const segments = Array.isArray(day.segments) ? day.segments : [];
            const parts = [];
            const names = [];
            let cursor = 0;
            for (const segment of segments) {
              const value = Math.max(0, finiteNumber(segment.value));
              const name = segment.isOther ? "Other" : (models[segment.rank] || "Model");
              parts.push({ className: seriesClass(segment.rank, segment.isOther), start: cursor, end: cursor + value });
              names.push(`${name} ${dollars(value)}`);
              cursor += value;
            }
            if (!parts.length) {
              parts.push({ className: "so", start: 0, end: finiteNumber(day.total) });
              names.push("no model breakdown");
            }
            return {
              slot: dayNumber(day.date) - start,
              detail: `${dayLabel(day.date)} · ${dollars(day.total)} · ${names.join(", ")}`,
              parts
            };
          });
          stackedBars(svg, columns, slotCount, ticks[ticks.length - 1], readout);
          appendSlotLabels(svg, dayLabel(range.start), dayLabel(range.end));
          const legend = models.map((name, rank) => ({ className: seriesClass(rank, false), label: name }));
          if (entry.hasOther) legend.push({ className: "so", label: "Other" });
          card.append(svg, readout.element, insightLegend(legend));
          return card;
        }

        function renderModelShare(share, range) {
          const series = Array.isArray(share.series) ? share.series : [];
          const points = Array.isArray(share.points) ? share.points : [];
          if (!series.length || !points.length) return null;
          const byID = new Map(series.map(entry => [entry.id, entry]));
          const dates = [...new Set(points.map(point => point.date))].sort();
          const start = dayNumber(range.start);
          const daily = share.bucket === "day" && start !== null;
          const slotCount = daily ? Math.max(1, finiteNumber(range.days, 30)) : dates.length;
          const card = insightCard("Model share over time", `Share of estimated spend per ${share.bucket || "day"}`);
          const readout = makeReadout("Hover or focus a bar to see each model's share.");
          const ticks = niceTicks(1);
          const svg = chartFrame("Model share of spend over time", ticks, percentText);
          const columns = dates.map((date, index) => {
            const parts = [];
            const names = [];
            for (const point of points.filter(candidate => candidate.date === date)) {
              const entry = byID.get(point.series) || {};
              parts.push({
                className: seriesClass(entry.rank, entry.isOther),
                start: finiteNumber(point.shareStart),
                end: finiteNumber(point.shareEnd)
              });
              names.push(`${entry.name || "Model"} ${percentText(point.share)}`);
            }
            return {
              slot: daily ? dayNumber(date) - start : index,
              detail: `${dayLabel(date)} · ${names.join(", ")}`,
              parts
            };
          });
          stackedBars(svg, columns, slotCount, ticks[ticks.length - 1], readout);
          const firstLabel = dayLabel(daily ? range.start : dates[0]);
          appendSlotLabels(svg, firstLabel, dayLabel(daily ? range.end : dates[dates.length - 1]));
          const legend = series.map(entry => ({
            className: seriesClass(entry.rank, entry.isOther),
            label: `${entry.name || entry.id} ${percentText(entry.share)}`
          }));
          card.append(svg, readout.element, insightLegend(legend));
          return card;
        }

        function renderHeatmap(heatmap, timeZone) {
          const weekdays = Array.isArray(heatmap.weekdays) && heatmap.weekdays.length === 7
            ? heatmap.weekdays
            : [1, 2, 3, 4, 5, 6, 7];
          const cells = new Map();
          for (const cell of Array.isArray(heatmap.cells) ? heatmap.cells : []) {
            cells.set(`${cell.weekday}:${cell.hour}`, cell);
          }
          const size = 11;
          const step = 12.5;
          const left = 30;
          const top = 12;
          const card = insightCard("Spend by weekday and hour",
            timeZone ? `Hours in ${timeZone}` : "Hours in the server's local time");
          const readout = makeReadout(heatmap.busiest
            ? `Busiest: ${weekdayName(heatmap.busiest.weekday)} ${hourText(heatmap.busiest.hour)} · `
              + dollars(heatmap.busiest.cost)
            : "Hover or focus a cell to see its spend.");
          const svg = insightSvg("svg", {
            viewBox: `0 0 ${left + 24 * step} ${top + 7 * step}`,
            role: "group",
            "aria-label": "Spend by weekday and hour"
          });
          svg.setAttribute("class", "insight-chart");
          for (const hour of [0, 6, 12, 18]) {
            const label = insightSvg("text", { class: "axis", x: left + hour * step, y: top - 4 });
            label.textContent = hourText(hour);
            svg.append(label);
          }
          weekdays.forEach((weekday, row) => {
            const label = insightSvg("text", { class: "axis", x: 0, y: top + row * step + size - 2 });
            label.textContent = weekdayName(weekday);
            svg.append(label);
            for (let hour = 0; hour < 24; hour += 1) {
              const cell = cells.get(`${weekday}:${hour}`);
              const level = cell ? Math.min(4, Math.max(1, Math.round(finiteNumber(cell.level, 1)))) : 0;
              const rect = insightSvg("rect", {
                class: cell ? `insight-mark heat-${level}` : "heat-0",
                x: left + hour * step,
                y: top + row * step,
                width: size,
                height: size,
                rx: 2
              });
              if (cell) {
                const when = `${weekdayName(weekday)} ${hourText(hour)}`;
                attachDetail(rect, readout, `${when} · ${dollars(cell.cost)} · ${percentText(cell.share)} of spend`);
              }
              svg.append(rect);
            }
          });
          const legend = [1, 2, 3, 4].map(level => ({ className: `heat-${level}`, label: "" }));
          const legendRow = insightLegend(legend);
          legendRow.append(node("span", "", heatmap.weekendShare == null
            ? "Darker cells had more spend"
            : `Darker cells had more spend · weekends ${percentText(heatmap.weekendShare)}`));
          card.append(svg, readout.element, legendRow);
          return card;
        }

        function sparkline(values, maxValue, className) {
          const width = 120;
          const height = 24;
          const svg = insightSvg("svg", { viewBox: `0 0 ${width} ${height}`, preserveAspectRatio: "none" });
          svg.setAttribute("class", `insight-spark ${className}`);
          svg.setAttribute("aria-hidden", "true");
          if (!values.length || !(maxValue > 0)) return svg;
          const x = index => values.length === 1 ? width / 2 : 1 + (index / (values.length - 1)) * (width - 2);
          const y = value => height - 1 - (Math.max(0, value) / maxValue) * (height - 2);
          let run = [];
          const flush = () => {
            if (run.length > 1) svg.append(insightSvg("polyline", { points: run.map(p => p.join(",")).join(" ") }));
            if (run.length === 1) svg.append(insightSvg("circle", { cx: run[0][0], cy: run[0][1], r: 1.5 }));
            run = [];
          };
          values.forEach((value, index) => {
            if (typeof value === "number" && Number.isFinite(value)) run.push([x(index), y(value)]);
            else flush();
          });
          flush();
          return svg;
        }

        function changeText(project) {
          switch (project.change) {
          case "percent":
            return signed(percentText(project.changeFraction), finiteNumber(project.changeFraction));
          case "new":
            return "New";
          case "ended":
            return "Ended";
          case "unchanged":
            return percentText(0);
          default:
            return "—";
          }
        }

        function renderProjectTrends(trends) {
          const projects = Array.isArray(trends.projects) ? trends.projects : [];
          if (!projects.length) return null;
          const half = finiteNumber(trends.comparisonDays);
          const card = insightCard("Project trends", half > 0
            ? `${dayLabel(trends.start)} – ${dayLabel(trends.end)} · change: last ${half} days vs the ${half} before`
            : `${dayLabel(trends.start)} – ${dayLabel(trends.end)}`);
          const labelCounts = new Map();
          for (const project of projects) labelCounts.set(project.label, (labelCounts.get(project.label) || 0) + 1);
          const maxValue = finiteNumber(trends.maxValue);
          for (const project of projects) {
            const rank = finiteNumber(project.rank, 1) - 1;
            const label = project.label || `Project ${rank + 1}`;
            const row = node("div", "trend-row");
            const swatch = node("span", `swatch ${seriesClass(rank, false)}`);
            swatch.setAttribute("aria-hidden", "true");
            const name = node("div", "trend-name");
            const title = node("span", "trend-label", label);
            if (project.path) title.setAttribute("title", project.path);
            name.append(title, node("span", "trend-provider", project.providerName || project.provider || ""));
            if (project.path && labelCounts.get(project.label) > 1) {
              name.append(node("span", "trend-path", project.path));
            }
            const points = Array.isArray(project.points) ? project.points : [];
            const change = changeText(project);
            row.append(
              swatch,
              name,
              sparkline(points.map(point => finiteNumber(point.value)), maxValue, seriesClass(rank, false)),
              node("span", "trend-total", dollars(project.total)),
              node("span", "trend-change", change));
            row.setAttribute("tabindex", "0");
            row.setAttribute("aria-label", `${label} · ${dollars(project.total)} · change ${change}`);
            card.append(row);
          }
          const omitted = finiteNumber(trends.omittedCount);
          if (omitted > 0) {
            card.append(node("p", "insight-sub", `${omitted} more ${omitted === 1 ? "project" : "projects"}`));
          }
          return card;
        }

        function insightTile(label, value, tile, note, deltaText) {
          const item = node("div", "insight-tile");
          item.append(node("span", "metric-label", label), node("span", "metric-value", value));
          const delta = tile && tile.previousValue != null && Number.isFinite(Number(tile.previousValue))
            ? `${deltaText(tile)} vs prior period`
            : note;
          if (delta) item.append(node("span", "insight-delta", delta));
          const trend = tile && Array.isArray(tile.trend) ? tile.trend : [];
          const values = trend.map(value => typeof value === "number" && Number.isFinite(value) ? value : null);
          const maxValue = Math.max(0, ...values.filter(value => value !== null));
          if (values.some(value => value !== null)) item.append(sparkline(values, maxValue, "s0"));
          return item;
        }

        function pointsDelta(tile) {
          const delta = Math.round((finiteNumber(tile.value) - finiteNumber(tile.previousValue)) * 100);
          return `${delta > 0 ? "+" : ""}${delta} pts`;
        }

        function relativeDelta(tile) {
          const previous = finiteNumber(tile.previousValue);
          if (!(previous > 0)) return "—";
          const change = (finiteNumber(tile.value) - previous) / previous;
          return signed(percentText(change), change);
        }

        function renderInsightTiles(tiles) {
          const row = node("div", "insight-tiles");
          if (tiles.apiEquivalentCost != null) {
            row.append(insightTile("Estimated spend", dollars(tiles.apiEquivalentCost), null,
              "API-equivalent, local usage logs"));
          }
          if (tiles.planValue) {
            row.append(insightTile("Plan value", `${finiteNumber(tiles.planValue.value).toFixed(1)}×`,
              tiles.planValue, "API-equivalent spend over plan price", tile => {
                const delta = finiteNumber(tile.value) - finiteNumber(tile.previousValue);
                return `${delta > 0 ? "+" : ""}${delta.toFixed(1)}×`;
              }));
          }
          if (tiles.cacheHitRate) {
            row.append(insightTile("Cache hit rate", percentText(tiles.cacheHitRate.value), tiles.cacheHitRate,
              "Prompt tokens read from cache", pointsDelta));
          }
          if (tiles.costPerMillionTokens) {
            row.append(insightTile("Cost per 1M tokens", dollars(tiles.costPerMillionTokens.value),
              tiles.costPerMillionTokens, "Fully priced days only", relativeDelta));
          }
          if (tiles.topModelShare) {
            row.append(insightTile("Top model share", percentText(tiles.topModelShare.value), tiles.topModelShare,
              tiles.topModelShare.modelName || "", pointsDelta));
          }
          return row.childElementCount ? row : null;
        }

        function renderInsights(insights) {
          const container = elements.insights;
          if (!container) return;
          if (!insights || typeof insights !== "object") {
            container.replaceChildren();
            return;
          }
          try {
            const range = insights.range || {};
            const head = node("div", "insights-head");
            head.append(node("h2", "group-title", "Insights"));
            head.append(node("span", "insights-note",
              `${dayLabel(range.start)} – ${dayLabel(range.end)} · API-equivalent estimates from local usage logs`));
            const sections = [];
            const tiles = insights.tiles ? renderInsightTiles(insights.tiles) : null;
            if (tiles) sections.push(tiles);
            const cards = [];
            for (const entry of Array.isArray(insights.costByModel) ? insights.costByModel : []) {
              cards.push(renderCostByModel(entry, range));
            }
            if (insights.modelShare) cards.push(renderModelShare(insights.modelShare, range));
            if (insights.heatmap) cards.push(renderHeatmap(insights.heatmap, insights.timeZone));
            if (insights.projectTrends) cards.push(renderProjectTrends(insights.projectTrends));
            const visibleCards = cards.filter(Boolean);
            if (visibleCards.length) {
              const grid = node("div", "insight-grid");
              grid.append(...visibleCards);
              sections.push(grid);
            }
            container.replaceChildren(...(sections.length ? [head, ...sections] : []));
          } catch (_) {
            // A malformed block must never take the provider cards above it down with it.
            container.replaceChildren();
          }
        }
    """#
}
