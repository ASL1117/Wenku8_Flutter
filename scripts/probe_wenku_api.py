"""Read-only smoke check for the public protocol used by the iOS bridge."""
import base64
import json
import time
import urllib.request
import urllib.parse
import xml.etree.ElementTree as ET


def request(action):
    # Preserve the legacy envelope: the service expects raw Base64, not a
    # second form-encoding pass. A descriptive client UA also avoids CF 1010.
    body = ("&appver=1.13&request=" + base64.b64encode(action.encode()).decode()
            + "&timetoken=" + str(time.time_ns() // 1_000_000)).encode()
    req = urllib.request.Request(
        "https://wenku8-relay.mewx.org/", body,
        {"Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
         "User-Agent": "Wenku8-Flutter/0.2.3"})
    with urllib.request.urlopen(req, timeout=25) as response:
        assert response.status == 200
        result = response.read(8 * 1024 * 1024 + 1)
        assert 0 < len(result) <= 8 * 1024 * 1024
        return result


def main():
    listing = ET.fromstring(request("action=novellist&sort=lastupdate&page=1&t=0"))
    assert listing.tag == "result" and listing.findall("item")
    aid = int(listing.find("item").attrib["aid"])
    second = ET.fromstring(request("action=novellist&sort=lastupdate&page=2&t=0"))
    assert second.findall("item")
    meta = ET.fromstring(request(f"action=book&do=meta&aid={aid}&t=0"))
    assert meta.tag == "metadata"
    intro = request(f"action=book&do=intro&aid={aid}&t=0").decode("utf-8")
    assert len(intro.strip()) > 10
    chapters = ET.fromstring(request(f"action=book&do=list&aid={aid}&t=0"))
    chapter = chapters.find(".//chapter")
    assert chapter is not None
    cid = int(chapter.attrib["cid"])
    body = request(f"action=book&do=text&aid={aid}&cid={cid}&t=0").decode("utf-8")
    assert len(body.strip()) > 10
    cover = request(f"action=book&do=cover&aid={aid}")
    assert len(cover) > 1000 and cover.startswith(b"\xff\xd8")
    libraries = ET.fromstring(request("action=xml&item=sort&t=0"))
    assert libraries.findall("item")
    search_key = urllib.parse.quote("侦探", safe="")
    search = ET.fromstring(request(
        f"action=search&searchtype=articlename&searchkey={search_key}&t=0"))
    assert search.tag == "result" and search.findall("item")
    # Do not log response text, account state, or request bodies.
    print(json.dumps({"protocol": "1.13", "book_id": aid, "chapter_id": cid,
                      "list_items": len(listing.findall("item")),
                      "chapter_characters": len(body), "cover_bytes": len(cover),
                      "search_items": len(search.findall("item")),
                      "result": "passed"}))


if __name__ == "__main__":
    main()
