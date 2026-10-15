#!/usr/bin/env python3
"""Скачивает все модели бандла poly.pizza (glb) и пишет manifest.json с
названием, автором и лицензией каждой — чтобы в репозитории было видно,
откуда пришёл ассет (ТЗ 31: у всех сторонних ассетов подходящая лицензия).

Использование: fetch_polypizza.py <url бандла> <папка>
Пример: fetch_polypizza.py https://poly.pizza/bundle/Cars-Bundle-FE5IWe6OMk build/asset_downloads/pp-cars
"""
import json
import os
import re
import sys
import urllib.request

UA = {"User-Agent": "Mozilla/5.0"}


def get(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60) as r:
        return r.read()


def main():
    bundle_url, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    html = get(bundle_url).decode("utf-8")
    m = re.search(r"window.__SERVER_APP_STATE__ =\s*(\{.*?\})\s*</script>", html, re.S)
    data = json.loads(m.group(1))["initialData"]["list"]
    manifest = {"bundle": data["Name"], "source": bundle_url, "models": []}
    for model in data["Models"]:
        # Превью и glb лежат рядом под одним uuid.
        glb_url = re.sub(r"\.(webp|jpg|png)$", ".glb", model["previewUrl"])
        name = re.sub(r"[^A-Za-z0-9]+", "_", model["title"]).strip("_")
        path = os.path.join(out, f"{name}.glb")
        if os.path.exists(path):
            # Одинаковые названия внутри бандла — дописываем id.
            path = os.path.join(out, f"{name}_{model['url'].split('/')[-1]}.glb")
        with open(path, "wb") as f:
            f.write(get(glb_url))
        manifest["models"].append({
            "file": os.path.basename(path),
            "title": model["title"],
            "author": model["creator"]["username"],
            "licence": model.get("licence"),
            "page": "https://poly.pizza" + model["url"],
        })
        print(path)
    with open(os.path.join(out, "manifest.json"), "w") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)


if __name__ == "__main__":
    main()
