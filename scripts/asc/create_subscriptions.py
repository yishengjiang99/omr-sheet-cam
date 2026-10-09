#!/usr/bin/env python3
"""Create (idempotently) the 'Music Reader Pro' auto-renewable subscriptions for
AI Camera - Music Reader (com.ragnus.vp) via the App Store Connect API.

Finds existing objects and creates only what is missing:
  subscription group 'Music Reader Pro' + en-US group localization
  com.ragnus.vp.pro.monthly  ONE_MONTH  USD 4.99
  com.ragnus.vp.pro.yearly   ONE_YEAR   USD 29.99
  en-US subscription localizations, availability in all territories (+ new territories),
  prices in every territory equalized from the USA price point, Family Sharing off.

Never submits anything for review. VERIFY_ONLY=true does read-only verification.
Product IDs must match Sources/App/Services/StoreKitManager.swift (IAPProductID).
Env: APP_STORE_CONNECT_KEY_ID, APP_STORE_CONNECT_ISSUER_ID, APP_STORE_CONNECT_API_KEY_P8,
     BUNDLE_ID (com.ragnus.vp), VERIFY_ONLY (true/false)
"""
from __future__ import annotations
import os, sys, time
import jwt, requests

BASE = "https://api.appstoreconnect.apple.com"
BUNDLE_ID = os.environ.get("BUNDLE_ID", "com.ragnus.vp").strip()
VERIFY_ONLY = os.environ.get("VERIFY_ONLY", "false").strip().lower() == "true"
LOCALE = "en-US"
GROUP_REF = "Music Reader Pro"
GROUP_DISPLAY = "Music Reader Pro"
PRODUCTS = [
    {"productId": "com.ragnus.vp.pro.monthly", "name": "Music Reader Pro Monthly",
     "period": "ONE_MONTH", "usd": "4.99", "desc": "Unlock all Pro features, billed monthly"},
    {"productId": "com.ragnus.vp.pro.yearly", "name": "Music Reader Pro Yearly",
     "period": "ONE_YEAR", "usd": "29.99", "desc": "Unlock all Pro features, billed yearly"},
]
_tok = {"v": None, "t": 0}


def token() -> str:
    now = int(time.time())
    if _tok["v"] and now - _tok["t"] < 600:
        return _tok["v"]
    p8 = os.environ["APP_STORE_CONNECT_API_KEY_P8"].replace("\\n", "\n").strip()
    _tok["v"] = jwt.encode({"iss": os.environ["APP_STORE_CONNECT_ISSUER_ID"].strip(), "iat": now,
                            "exp": now + 1100, "aud": "appstoreconnect-v1"}, p8, algorithm="ES256",
                           headers={"kid": os.environ["APP_STORE_CONNECT_KEY_ID"].strip()})
    _tok["t"] = now
    return _tok["v"]


class ApiError(Exception):
    pass


def api(method, path, body=None, ok404=False):
    assert "reviewSubmission" not in path and "Submission" not in path, "this script never submits"
    if VERIFY_ONLY and method != "GET":
        raise SystemExit(f"VERIFY_ONLY but tried {method} {path}")
    for attempt in range(5):
        r = requests.request(method, path if path.startswith("http") else BASE + path, json=body,
                             headers={"Authorization": "Bearer " + token()}, timeout=120)
        if r.status_code in (429, 500, 502, 503, 504) and attempt < 4:
            time.sleep(3 * (attempt + 1))
            continue
        break
    if ok404 and r.status_code == 404:
        return None
    if r.status_code >= 300:
        raise ApiError(f"{method} {path} -> {r.status_code}: {r.text[:3000]}")
    return r.json() if r.text else {}


def get_all(path):
    out, inc, url = [], [], path
    while url:
        j = api("GET", url)
        d = j.get("data")
        out.extend(d if isinstance(d, list) else ([d] if d else []))
        inc.extend(j.get("included", []))
        url = (j.get("links") or {}).get("next")
    return out, inc


def rel(t, i):
    return {"data": {"type": t, "id": i}}


def create(t, attrs, rels):
    print(f"CREATE {t} {attrs}")
    return api("POST", f"/v1/{t}", {"data": {"type": t, "attributes": attrs, "relationships": rels}})["data"]


def ensure_group(app_id):
    groups, _ = get_all(f"/v1/apps/{app_id}/subscriptionGroups?limit=200")
    g = next((g for g in groups if g["attributes"]["referenceName"] == GROUP_REF), None)
    if g:
        print("FOUND group", g["id"], GROUP_REF)
    else:
        g = create("subscriptionGroups", {"referenceName": GROUP_REF}, {"app": rel("apps", app_id)})
    locs, _ = get_all(f"/v1/subscriptionGroups/{g['id']}/subscriptionGroupLocalizations?limit=200")
    loc = next((l for l in locs if l["attributes"]["locale"] == LOCALE), None)
    if loc:
        print("FOUND group localization", loc["id"], loc["attributes"].get("name"), loc["attributes"].get("state"))
    else:
        create("subscriptionGroupLocalizations", {"locale": LOCALE, "name": GROUP_DISPLAY},
               {"subscriptionGroup": rel("subscriptionGroups", g["id"])})
    return g, groups


def ensure_sub(group_id, all_groups, p):
    # look in every group of the app so a product created elsewhere is not duplicated
    for grp in all_groups + [{"id": group_id}]:
        subs, _ = get_all(f"/v1/subscriptionGroups/{grp['id']}/subscriptions?limit=200")
        s = next((s for s in subs if s["attributes"]["productId"] == p["productId"]), None)
        if s:
            if grp["id"] != group_id:
                print(f"WARNING {p['productId']} exists in another group {grp['id']}")
            print("FOUND subscription", s["id"], p["productId"], s["attributes"].get("state"))
            a = s["attributes"]
            if a.get("familySharable"):
                print(f"WARNING {p['productId']} has Family Sharing ON (Apple does not allow turning it off)")
            return s
    return create("subscriptions", {"productId": p["productId"], "name": p["name"],
                                    "subscriptionPeriod": p["period"], "familySharable": False},
                  {"group": rel("subscriptionGroups", group_id)})


def ensure_sub_loc(sub_id, p):
    locs, _ = get_all(f"/v1/subscriptions/{sub_id}/subscriptionLocalizations?limit=200")
    loc = next((l for l in locs if l["attributes"]["locale"] == LOCALE), None)
    if loc:
        print("FOUND subscription localization", loc["id"], loc["attributes"].get("name"))
        return
    create("subscriptionLocalizations", {"locale": LOCALE, "name": p["name"], "description": p["desc"]},
           {"subscription": rel("subscriptions", sub_id)})


def ensure_availability(sub_id, territory_ids):
    j = api("GET", f"/v1/subscriptions/{sub_id}/subscriptionAvailability", ok404=True)
    if j and j.get("data"):
        av = j["data"]
        cur, _ = get_all(f"/v1/subscriptionAvailabilities/{av['id']}/availableTerritories?limit=200")
        have = {t["id"] for t in cur}
        missing = set(territory_ids) - have
        print("FOUND availability", av["id"], len(have), "territories; missing", len(missing),
              "availableInNewTerritories=", av["attributes"].get("availableInNewTerritories"))
        if not missing and av["attributes"].get("availableInNewTerritories"):
            return
    print("SET availability:", len(territory_ids), "territories")
    api("POST", "/v1/subscriptionAvailabilities", {"data": {
        "type": "subscriptionAvailabilities", "attributes": {"availableInNewTerritories": True},
        "relationships": {"subscription": rel("subscriptions", sub_id),
                          "availableTerritories": {"data": [{"type": "territories", "id": t} for t in sorted(territory_ids)]}}}})


def usa_price_point(sub_id, usd):
    pts, _ = get_all(f"/v1/subscriptions/{sub_id}/pricePoints?filter[territory]=USA&limit=200")
    for pp in pts:
        if pp["attributes"]["customerPrice"] in (usd, usd + "0") or float(pp["attributes"]["customerPrice"]) == float(usd):
            return pp
    raise SystemExit(f"no USA price point {usd} for {sub_id}")


def existing_prices(sub_id):
    prices, inc = get_all(f"/v1/subscriptions/{sub_id}/prices?include=territory,subscriptionPricePoint&limit=200")
    pp = {i["id"]: i["attributes"] for i in inc if i["type"] == "subscriptionPricePoints"}
    out = {}
    for pr in prices:
        terr = ((pr.get("relationships") or {}).get("territory") or {}).get("data")
        ppd = ((pr.get("relationships") or {}).get("subscriptionPricePoint") or {}).get("data")
        if terr:
            out[terr["id"]] = (pp.get(ppd["id"], {}).get("customerPrice") if ppd else None, pr["attributes"].get("startDate"))
    return out


def ensure_prices(sub_id, p):
    base = usa_price_point(sub_id, p["usd"])
    eq, eq_inc = get_all(f"/v1/subscriptionPricePoints/{base['id']}/equalizations?include=territory&limit=200")
    targets = {"USA": base["id"]}
    for e in eq:
        terr = ((e.get("relationships") or {}).get("territory") or {}).get("data")
        if terr:
            targets[terr["id"]] = e["id"]
    have = existing_prices(sub_id)
    todo = {t: ppid for t, ppid in targets.items() if t not in have}
    print(f"PRICES {p['productId']}: USA point {base['id']} = {base['attributes']['customerPrice']}; "
          f"{len(targets)} territories, {len(have)} already priced, {len(todo)} to create")
    # USA first so a failure (e.g. agreements) surfaces immediately
    for t in sorted(todo, key=lambda x: (x != "USA", x)):
        api("POST", "/v1/subscriptionPrices", {"data": {
            "type": "subscriptionPrices", "attributes": {"preserveCurrentPrice": False},
            "relationships": {"subscription": rel("subscriptions", sub_id),
                              "subscriptionPricePoint": rel("subscriptionPricePoints", todo[t]),
                              "territory": rel("territories", t)}}})
    if todo:
        print(f"PRICES {p['productId']}: created {len(todo)}")


def verify(app_id):
    print("\n===== VERIFY =====")
    ok = True
    groups, _ = get_all(f"/v1/apps/{app_id}/subscriptionGroups?limit=200")
    for g in groups:
        locs, _ = get_all(f"/v1/subscriptionGroups/{g['id']}/subscriptionGroupLocalizations?limit=200")
        print("GROUP", g["id"], repr(g["attributes"]["referenceName"]),
              [(l["attributes"]["locale"], l["attributes"].get("name"), l["attributes"].get("state")) for l in locs])
        subs, _ = get_all(f"/v1/subscriptionGroups/{g['id']}/subscriptions?limit=200")
        for s in subs:
            a = s["attributes"]
            sl, _ = get_all(f"/v1/subscriptions/{s['id']}/subscriptionLocalizations?limit=200")
            prices = existing_prices(s["id"])
            av = api("GET", f"/v1/subscriptions/{s['id']}/subscriptionAvailability", ok404=True)
            nterr = 0
            if av and av.get("data"):
                t, _ = get_all(f"/v1/subscriptionAvailabilities/{av['data']['id']}/availableTerritories?limit=200")
                nterr = len(t)
            shot = api("GET", f"/v1/subscriptions/{s['id']}/appStoreReviewScreenshot", ok404=True)
            print(f"  SUB {s['id']} {a['productId']} name={a.get('name')!r} period={a.get('subscriptionPeriod')} "
                  f"state={a.get('state')} familySharable={a.get('familySharable')} level={a.get('groupLevel')}")
            print(f"      localizations={[(l['attributes']['locale'], l['attributes'].get('name'), l['attributes'].get('description'), l['attributes'].get('state')) for l in sl]}")
            print(f"      USA price={prices.get('USA')} priced_territories={len(prices)} available_territories={nterr} "
                  f"review_screenshot={'yes' if shot and shot.get('data') else 'MISSING'} review_note={a.get('reviewNote')!r}")
            want = next((p for p in PRODUCTS if p["productId"] == a["productId"]), None)
            if want and (not prices.get("USA") or float(prices["USA"][0]) != float(want["usd"])):
                ok = False
    found = {s["attributes"]["productId"] for g in groups
             for s in get_all(f"/v1/subscriptionGroups/{g['id']}/subscriptions?limit=200")[0]}
    for p in PRODUCTS:
        if p["productId"] not in found:
            print("MISSING product", p["productId"])
            ok = False
    return ok


def main():
    apps = api("GET", f"/v1/apps?filter[bundleId]={BUNDLE_ID}")["data"]
    if not apps:
        raise SystemExit(f"app {BUNDLE_ID} not found")
    app_id = apps[0]["id"]
    print("APP", app_id, apps[0]["attributes"].get("name"))
    if not VERIFY_ONLY:
        terr, _ = get_all("/v1/territories?limit=200")
        territory_ids = [t["id"] for t in terr]
        print("TERRITORIES", len(territory_ids))
        g, groups = ensure_group(app_id)
        for p in PRODUCTS:
            s = ensure_sub(g["id"], groups, p)
            ensure_sub_loc(s["id"], p)
            ensure_availability(s["id"], territory_ids)
            ensure_prices(s["id"], p)
    ok = verify(app_id)
    if not ok:
        print("VERIFY FAILED: USA price mismatch or missing")
        sys.exit(1)
    print("VERIFY OK")


if __name__ == "__main__":
    try:
        main()
    except ApiError as e:
        msg = str(e)
        print("API ERROR:", msg)
        if "agreement" in msg.lower():
            print("BLOCKER: the Paid Apps Agreement appears not to be active (ASC > Business).")
        sys.exit(1)
