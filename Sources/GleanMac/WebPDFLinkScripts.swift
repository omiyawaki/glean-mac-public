import Foundation

enum WebPDFLinkScripts {
    private static let minimumClickableScore = 80

    private static var candidateHelpers: String {
        """
        const norm = value => (value || "").replace(/\\s+/g, " ").trim();
        const visible = element => !!(
          element.offsetWidth ||
          element.offsetHeight ||
          element.getClientRects().length
        );
        const scorePDFCandidate = (text, href, isVisible) => {
          if (!isVisible) return 0;
          const lowerText = text.toLowerCase();
          const lowerHref = href.toLowerCase();
          let score = 0;
          if (/\\b(download|view|open)\\s+pdf\\b/.test(lowerText)) score += 100;
          if (/\\b(full\\s+text|article)\\s+pdf\\b/.test(lowerText)) score += 90;
          if (lowerText === "pdf") score += 90;
          if (lowerHref.includes("/doi/epdf/")) score += 80;
          if (lowerHref.includes("/doi/pdf/")) score += 80;
          if (/\\bpdf\\b/.test(lowerText)) score += 30;
          if (lowerHref.includes(".pdf") || lowerHref.endsWith("/pdf")) score += 10;
          return score;
        };
        const pdfCandidateFor = (element, index) => {
          const text = norm([
            element.innerText,
            element.textContent,
            element.getAttribute("aria-label"),
            element.getAttribute("title")
          ].filter(Boolean).join(" "));
          const href = element.href || element.getAttribute("href") || "";
          const isVisible = visible(element);
          const score = scorePDFCandidate(text, href, isVisible);
          return {
            element,
            index,
            tag: element.tagName.toLowerCase(),
            text,
            href,
            visible: isVisible,
            score
          };
        };
        """
    }

    static var pdfProbeScript: String {
        """
        (() => {
          \(candidateHelpers)
          const nodes = Array.from(document.querySelectorAll('a, button, [role="button"]'));
          const candidates = nodes.map(pdfCandidateFor)
            .filter(candidate => candidate.score > 0)
            .sort((a, b) => b.score - a.score || a.index - b.index)
            .slice(0, 12)
            .map(candidate => ({
              index: candidate.index,
              tag: candidate.tag,
              text: candidate.text.slice(0, 160),
              href: candidate.href,
              visible: candidate.visible,
              score: candidate.score
            }));
          return JSON.stringify(candidates);
        })()
        """
    }

    static var pdfClickScript: String {
        """
        (() => {
          \(candidateHelpers)
          const nodes = Array.from(document.querySelectorAll('a, button, [role="button"]'));
          const scored = nodes.map(pdfCandidateFor)
            .filter(candidate => candidate.score >= \(minimumClickableScore))
            .sort((a, b) => b.score - a.score || a.index - b.index);

          const hit = scored[0];
          if (!hit) {
            return JSON.stringify({ clicked: false, reason: "no PDF candidates" });
          }
          hit.element.scrollIntoView({ block: "center", inline: "center" });
          // Many publishers (ScienceDirect, IOPscience, …) mark their
          // "View PDF" anchor target="_blank". WKWebView blocks the
          // popup by default, so the click looks like it did nothing.
          // Strip the target attribute first so the navigation happens
          // in the main frame and our response-download path can fire.
          if (hit.element.tagName.toLowerCase() === "a") {
            hit.element.removeAttribute("target");
          }
          hit.element.click();
          return JSON.stringify({
            clicked: true,
            tag: hit.tag,
            text: hit.text.slice(0, 160),
            href: hit.href,
            score: hit.score
          });
        })()
        """
    }
}
