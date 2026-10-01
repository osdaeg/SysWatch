#!/usr/bin/env python3

import sys
import urllib.request
import xml.etree.ElementTree as ET


def clean(value):
    return " ".join((value or "").split())


def main():

    if len(sys.argv) != 2:
        return 1

    url = sys.argv[1]

    request = urllib.request.Request(
        url,
        headers={
            "User-Agent": "SysWatch RSS Reader/0.1"
        }
    )

    try:

        with urllib.request.urlopen(request, timeout=15) as response:
            data = response.read()

        root = ET.fromstring(data)

    except Exception:
        return 1

    channel = root.find("channel")

    if channel is None:
        return 1

    feed_title = clean(
        channel.findtext("title", default="")
    )

    if not feed_title:
        return 1

    print(f"__FEED_TITLE__\t{feed_title}")

    for item in channel.findall("item"):

        title = clean(
            item.findtext("title", default="")
        )

        link = clean(
            item.findtext("link", default="")
        )

        guid = clean(
            item.findtext("guid", default="")
        )

        pubdate = clean(
            item.findtext("pubDate", default="")
        )

        if not guid:
            guid = link

        if not title or not link or not guid:
            continue

        print(
            f"{guid}\t{link}\t{title}\t{pubdate}"
        )


if __name__ == "__main__":
    sys.exit(main())