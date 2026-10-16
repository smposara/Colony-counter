"""Builds docs/manual/index.html from docs/manual/text/*.json and the
annotated screenshots in docs/manual/img/ (see README.md).

    python3 test/manual/build_manual.py ../docs/manual 0.9.2 [fragment.html]
"""

import html
import json
import pathlib
import sys

ICONS = {
    # 24 × 24 line icons (stroke = currentColor).
    'home': '<path d="M3 11 12 4l9 7v9h-6v-6H9v6H3z"/>',
    'camera': '<path d="M4 8h3l2-3h6l2 3h3v11H4z"/><circle cx="12" cy="13" r="3.5"/>',
    'flask': '<path d="M9 3h6M10 3v6l-5 9a2 2 0 0 0 2 3h10a2 2 0 0 0 2-3l-5-9V3"/><path d="M7 15h10"/>',
    'qr': '<path d="M4 4h6v6H4zM14 4h6v6h-6zM4 14h6v6H4z"/><path d="M14 14h2v2h-2zM18 18h2v2h-2zM14 18h2M18 14h2"/>',
    'grid': '<circle cx="7" cy="7" r="3.5"/><circle cx="17" cy="7" r="3.5"/><circle cx="7" cy="17" r="3.5"/><circle cx="17" cy="17" r="3.5"/>',
    'chart': '<path d="M4 4v16h16"/><path d="m7 15 4-5 3 3 5-7"/>',
    'palette': '<circle cx="12" cy="12" r="8.5"/><circle cx="8.5" cy="10" r="1.3"/><circle cx="12" cy="7.5" r="1.3"/><circle cx="15.5" cy="10" r="1.3"/><path d="M12 20.5a2.5 2.5 0 0 1 0-5h2"/>',
    'plate': '<circle cx="12" cy="12" r="8.5"/><rect x="7" y="7" width="10" height="10" rx="1.5"/>',
    'clock': '<circle cx="12" cy="12" r="8.5"/><path d="M12 7v5l3 2"/>',
    'drops': '<circle cx="12" cy="12" r="8.5"/><circle cx="12" cy="7" r="1.6"/><circle cx="16.5" cy="10.5" r="1.6"/><circle cx="15" cy="16" r="1.6"/><circle cx="9" cy="16" r="1.6"/><circle cx="7.5" cy="10.5" r="1.6"/>',
    'film': '<rect x="5" y="3" width="14" height="18" rx="1.5"/><circle cx="12" cy="11" r="4.5"/><path d="M8 18h8"/>',
    'target': '<circle cx="12" cy="12" r="8.5"/><circle cx="12" cy="12" r="4.5"/><circle cx="12" cy="12" r="1.2"/>',
    'ruler': '<path d="m3 16 13-13 5 5L8 21z"/><path d="m7 12 2 2M10 9l2 2M13 6l2 2"/>',
    'check': '<circle cx="12" cy="12" r="8.5"/><path d="m8 12 3 3 5-6"/>',
    'box': '<path d="M4 8 12 4l8 4v8l-8 4-8-4z"/><path d="M4 8l8 4 8-4M12 12v8"/>',
}

UI = {
    'title': {'en': 'Colony Counter manual', 'th': 'คู่มือ Colony Counter'},
    'lead': {
        'en': 'Every feature, step by step. Follow the numbers on each screen.',
        'th': 'ทุกฟีเจอร์ ทีละขั้นตอน ทำตามหมายเลขบนแต่ละหน้าจอ',
    },
    'contents': {'en': 'Contents', 'th': 'สารบัญ'},
    'top': {'en': 'Back to contents', 'th': 'กลับไปสารบัญ'},
    'step': {'en': 'Step', 'th': 'ขั้นที่'},
    'version': {'en': 'App version', 'th': 'แอปเวอร์ชัน'},
}


def t(d, cls=''):
    """Both languages; CSS shows the chosen one."""
    if d is None:
        return ''
    c = f' {cls}' if cls else ''
    return (f'<span lang="en" class="l-en{c}">{html.escape(d["en"])}</span>'
            f'<span lang="th" class="l-th{c}">{html.escape(d["th"])}</span>')


def icon(name):
    return (f'<svg class="ico" viewBox="0 0 24 24" aria-hidden="true">'
            f'{ICONS.get(name, ICONS["home"])}</svg>')


def build(root, version, fragment=None):
    root = pathlib.Path(root)
    chapters = sorted(
        (json.loads(p.read_text()) for p in (root / 'text').glob('*.json')),
        key=lambda c: c['order'])
    toc, body = [], []
    for c in chapters:
        cid = c['id']
        toc.append(
            f'<a class="toc-item" href="#{cid}">{icon(c.get("icon", ""))}'
            f'<span class="toc-text"><b>{t(c["title"])}</b>'
            f'<small>{t(c.get("summary"))}</small></span></a>')
        secs = []
        n = 0
        for s in c['sections']:
            steps = []
            for st in s['steps']:
                n += 1
                shot = st['shot']
                marks = st.get('marks', [])
                caps = ''.join(
                    f'<li><span class="badge">{i}</span>{t(m)}</li>'
                    for i, m in enumerate(marks, 1))
                cap = st.get('caption')
                tip = st.get('tip')
                steps.append(
                    f'<figure class="step">'
                    f'<div class="phone"><img loading="lazy" width="360" height="780" '
                    f'src="img/{shot}.en.webp" data-src-th="img/{shot}.th.webp" '
                    f'data-src-en="img/{shot}.en.webp" alt=""></div>'
                    f'<figcaption><span class="step-no">{n}</span>'
                    + (f'<p class="cap">{t(cap)}</p>' if cap else '')
                    + (f'<ol class="marks">{caps}</ol>' if caps else '')
                    + (f'<p class="tip">{t(tip)}</p>' if tip else '')
                    + '</figcaption></figure>')
            secs.append(
                f'<section class="sec"><h3>{t(s["title"])}</h3>'
                f'<div class="steps">{"".join(steps)}</div></section>')
        body.append(
            f'<article class="chapter" id="{cid}">'
            f'<header class="ch-head">{icon(c.get("icon", ""))}'
            f'<div><h2>{t(c["title"])}</h2>'
            f'<p class="summary">{t(c.get("summary"))}</p></div></header>'
            + ''.join(secs)
            + f'<a class="to-top" href="#contents">↑ {t(UI["top"])}</a>'
            '</article>')
    page = (TEMPLATE
            .replace('{{TITLE}}', t(UI['title']))
            .replace('{{LEAD}}', t(UI['lead']))
            .replace('{{CONTENTS}}', t(UI['contents']))
            .replace('{{VERSION}}', f'{t(UI["version"])} {html.escape(version)}')
            .replace('{{TOC}}', ''.join(toc))
            .replace('{{BODY}}', ''.join(body)))
    # A standalone page for the repo and the web app; the bare fragment for
    # hosts that add their own document skeleton.
    (root / 'index.html').write_text(
        '<!doctype html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n'
        '<meta name="viewport" content="width=device-width, initial-scale=1, '
        'viewport-fit=cover">\n</head>\n<body>\n' + page + '\n</body>\n</html>\n')
    if fragment:
        pathlib.Path(fragment).write_text(page)
    shots = sum(len(s['steps']) for c in chapters for s in c['sections'])
    print(f'{len(chapters)} chapters, {shots} steps → {root / "index.html"}')


TEMPLATE = (pathlib.Path(__file__).with_name('manual_template.html')
            .read_text())

if __name__ == '__main__':
    build(*sys.argv[1:4])
