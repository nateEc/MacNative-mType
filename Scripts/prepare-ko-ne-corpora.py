#!/usr/bin/env python3
"""Pinned independent Korean and Nepali literal pools, observations and complete provenance."""
import argparse
import bz2
import gzip
import heapq
import zipfile
import subprocess
from collections import Counter
import hashlib
import json
from pathlib import Path
import re
import unicodedata
import unittest
from urllib.parse import quote

ROOT = Path(__file__).resolve().parents[1]
PARTS = set('noun verb adj adv name pron num det conj intj prep postp particle phrase abbrev counter classifier'.split())
BAD = {'misspelling', 'proscribed', 'nonstandard'}
SPECS = {
    "ko": {
        "name": "Korean",
        "sentenceCode": "kor",
        "dictionarySHA": "c160b1dadd49b14109c2c1a29a616cc44064a738f91d2b98c1cdf457b90fde7f",
        "sentencesSHA": "708a62bf6f003c29e4dae11d554052fbbf6e22adff5518d7b80f09aaed9eb5eb",
        "extraction": "2026-10-30; enwiktionary dump 2026-10-01; 19f9a30 / 6f96ddf",
        "legacy": [
            "\uc544\uce68",
            "\ucc3d\ubb38",
            "\uc885\uc774",
            "\ud574\ubcc0",
            "\ubc14\ub78c",
            "\uc5f0\uc2b5",
            "\uc9d1\uc911",
            "\ucc9c\ucc9c\ud788",
            "\ubd84\uba85\ud788",
            "\ud638\uc218",
            "\uac70\ub9ac",
            "\ucc45\uc0c1",
            "\ube5b",
            "\uc5ec\ud589",
            "\uc778\ub0b4",
            "\uc7a0\uc2dc",
            "\ub3c4\uc2dc",
            "\ube44",
            "\uace0\uc694",
            "\ubc29\ud5a5",
            "\ubcc4\ube5b",
            "\ucabd\uc9c0",
            "\uc815\uc6d0",
            "\ud638\ud761"
        ],
        "pools": {
            "basic": [
                470,
                1,
                5
            ],
            "1k": [
                975,
                1,
                5
            ],
            "5k": [
                4201,
                1,
                6
            ]
        },
        "referenceKeys": {
            "basic": "\uac00\uac01\uac04\uac11\uac16\uac19\uac1c\uac70\uac74\uac78\uac83\uaca9\uacb0\uacbd\uacc4\uace0\uace7\uacf3\uacf5\uacfc\uad00\uad11\uad50\uad6c\uad6d\uad74\uadf8\uadfc\uae00\uae08\uae30\uae38\uae4a\uaed8\uaf2d\uaf43\uafb8\ub05d\ub07c\ub08c\ub098\ub0a0\ub0a8\ub0b3\ub0b4\ub0e5\ub108\ub118\ub123\ub124\ub140\ub144\ub178\ub180\ub192\ub193\ub204\ub208\ub290\ub294\ub298\ub2a5\ub2c8\ub2d8\ub2e4\ub2e8\ub2f5\ub2f9\ub300\ub354\ub370\ub3c4\ub3c8\ub3cc\ub3d9\ub450\ub4a4\ub4e0\ub4e3\ub4e4\ub4ef\ub4f1\ub514\ub530\ub545\ub54c\ub5a0\ub5a4\ub5a8\ub5bb\ub610\ub73b\ub77c\ub78c\ub791\ub798\ub7a8\ub7ec\ub7f0\ub7fc\ub807\ub824\ub825\ub828\ub835\ub839\ub85c\ub860\ub86d\ub8cc\ub8e8\ub974\ub978\ub984\ub9ac\ub9bc\ub9c8\ub9cc\ub9ce\ub9d0\ub9db\ub9de\ub9e4\uba38\uba39\uba3c\uba85\uba87\ubaa8\ubaa9\ubab8\ubabb\ubb34\ubb38\ubb3b\ubb3c\ubb50\ubbf8\ubbfc\ubbff\ubc0f\ubc14\ubc16\ubc1b\ubc1c\ubc1d\ubc24\ubc25\ubc29\ubc30\ubc84\ubc88\ubc95\ubcc0\ubcf4\ubd80\ubd84\ubd88\ube44\ube60\ubfd0\uc0ac\uc0b0\uc0b4\uc0b6\uc0c1\uc0c8\uc0dd\uc11c\uc120\uc131\uc138\uc13c\uc18c\uc18d\uc190\uc218\uc220\uc27d\uc2a8\uc2b4\uc2b5\uc2dc\uc2dd\uc2e0\uc2e4\uc2ec\uc2f6\uc4f0\uc528\uc544\uc548\uc549\uc54a\uc54c\uc55e\uc560\uc57c\uc591\uc598\uc5b4\uc5b8\uc5bb\uc5bc\uc5c4\uc5c5\uc5c6\uc5c7\uc5ec\uc5ed\uc5f0\uc5f4\uc601\uc606\uc608\uc624\uc62c\uc65c\uc694\uc6a9\uc6b0\uc6b1\uc6b4\uc6c0\uc6c3\uc6d0\uc704\uc720\uc721\uc73c\uc744\uc74c\uc758\uc774\uc778\uc77c\uc77d\uc785\uc788\uc790\uc791\uc798\uc7a1\uc7a5\uc7ac\uc800\uc801\uc804\uc810\uc815\uc81c\uc870\uc871\uc880\uc88b\uc8fc\uc8fd\uc904\uc911\uc989\uc998\uc9c0\uc9c1\uc9d1\uc9d3\ucabd\ucc28\ucc3e\ucc44\ucc45\ucc98\uccb4\ucd5c\uce58\uce5c\uce68\ucee4\ucef4\ud06c\ud07c\ud0a4\ud0c0\ud0dc\ud130\ud1b5\ud2b8\ud2b9\ud37c\ud3b8\ud45c\ud488\ud4e8\ud504\ud53c\ud544\ud558\ud559\ud55c\ud560\ud568\ud589\ud5a5\ud600\ud604\ud615\ud63c\ud654\ud658\ud65c\ud669\ud68c\ud68d\ud6c4\ud750\ud788\ud798",
            "1k": "\uac00\uac01\uac04\uac08\uac10\uac12\uac15\uac16\uac19\uac1c\uac70\uac71\uac74\uac77\uac78\uac80\uac81\uac83\uac8c\uaca8\uaca9\uacaa\uacac\uacb0\uacbd\uacc1\uacc4\uace0\uace8\uacf1\uacf3\uacf5\uacfc\uad00\uad1c\uad50\uad6c\uad6d\uad70\uad8c\uadc0\uaddc\uade0\uadf8\uadf9\uadfc\uae00\uae08\uae09\uae30\uae38\uae4c\uae5d\uae68\uaebc\uaef4\uaf34\uafb8\uafc8\ub00c\ub04c\ub053\ub054\ub057\ub05d\ub07c\ub098\ub09c\ub0a0\ub0a8\ub0ae\ub0b4\ub0c4\ub0d0\ub108\ub110\ub113\ub118\ub124\ub140\ub141\ub144\ub150\ub178\ub17c\ub180\ub188\ub18d\ub192\ub193\ub204\ub208\ub215\ub274\ub290\ub298\ub2a5\ub2a6\ub2c8\ub2d8\ub2e4\ub2e5\ub2e6\ub2e8\ub2eb\ub2ec\ub2ed\ub2f4\ub2f5\ub2f9\ub2ff\ub300\ub354\ub358\ub370\ub3c4\ub3c5\ub3cc\ub3d5\ub3d9\ub418\ub450\ub458\ub460\ub461\ub4dc\ub4dd\ub4e0\ub4e4\ub4ef\ub4f1\ub514\ub530\ub538\ub540\ub54c\ub5a0\ub5a1\ub5a8\ub5bc\ub611\ub728\ub73b\ub77c\ub77d\ub78c\ub791\ub797\ub798\ub79c\ub7a8\ub7ab\ub7ec\ub7f0\ub7fd\ub807\ub808\ub824\ub825\ub828\ub835\ub840\ub85c\ub85d\ub860\ub86d\ub86f\ub8cc\ub8e8\ub8f9\ub958\ub96d\ub974\ub978\ub984\ub987\ub9ac\ub9b0\ub9bc\ub9c8\ub9c9\ub9cc\ub9ce\ub9d0\ub9d1\ub9d9\ub9db\ub9dd\ub9de\ub9e1\ub9e4\uba38\uba40\uba48\uba70\uba74\uba85\ubaa8\ubaa9\ubabb\ubb34\ubb38\ubb3c\ubbc0\ubbf8\ubbfc\ubc00\ubc11\ubc14\ubc15\ubc18\ubc1b\ubc1c\ubc1d\ubc29\ubc2d\ubc30\ubc84\ubc88\ubc8c\ubc94\ubc95\ubc97\ubcbd\ubcc0\ubcc4\ubccd\ubcd1\ubcf4\ubcf5\ubcf8\ubd04\ubd80\ubd84\ubd88\ubd99\ube0c\ube44\ube4c\ube5b\ube60\ube68\ube7c\ubf51\ubfcc\uc058\uc0ac\uc0b0\uc0b4\uc0bc\uc0c1\uc0c8\uc0c9\uc0dd\uc11c\uc11d\uc120\uc124\uc12d\uc131\uc138\uc13c\uc148\uc18c\uc18d\uc190\uc1a1\uc218\uc21c\uc220\uc228\uc232\uc26c\uc2a4\uc2b7\uc2dc\uc2dd\uc2e0\uc2e3\uc2e4\uc2eb\uc2ec\uc2ed\uc2f8\uc300\uc313\uc368\uc370\uc4f0\uc500\uc528\uc52c\uc53b\uc544\uc545\uc548\uc54c\uc559\uc55e\uc57c\uc57d\uc591\uc597\uc598\uc5b4\uc5b5\uc5b8\uc5bc\uc5c4\uc5c5\uc5c6\uc5d0\uc5ec\uc5ed\uc5f0\uc5f4\uc5fc\uc601\uc608\uc61b\uc624\uc628\uc62c\uc62e\uc633\uc637\uc644\uc655\uc65c\uc678\uc694\uc6a9\uc6b0\uc6b4\uc6b8\uc6c0\uc6c3\uc6d0\uc6d4\uc6e8\uc704\uc720\uc721\uc73c\uc740\uc744\uc74c\uc751\uc758\uc774\uc775\uc778\uc77c\uc783\uc784\uc785\uc787\uc788\uc78a\uc790\uc791\uc794\uc798\uc7a0\uc7a1\uc7a5\uc7ac\uc7c1\uc800\uc801\uc804\uc808\uc80a\uc810\uc811\uc815\uc816\uc81c\uc838\uc870\uc871\uc874\uc885\uc8c4\uc8fc\uc8fd\uc900\uc904\uc911\uc950\uc988\uc990\uc99d\uc9c0\uc9c1\uc9c4\uc9c8\uc9d1\uc9d3\uc9d5\uc9dc\uc9e7\uc9f8\uca0c\uca4c\ucabd\ucc0c\ucc0d\ucc28\ucc29\ucc2c\ucc2e\ucc30\ucc38\ucc3e\ucc45\ucc59\ucc98\ucc99\ucc9c\ucca0\uccab\uccad\uccb4\uccd0\ucd08\ucd0c\ucd5c\ucd94\ucd95\ucd9c\ucda4\ucda9\ucde8\uce35\uce58\uce59\uce60\uce68\ucee4\ucf54\ud06c\ud07c\ud0a4\ud0c0\ud0d3\ud0d5\ud0dc\ud0dd\ud130\ud154\ud1a4\ud1b5\ud22c\ud2b8\ud2b9\ud2c0\ud2f0\ud300\ud30c\ud310\ud314\ud3b4\ud3b8\ud3c9\ud3ec\ud3ed\ud45c\ud478\ud480\ud488\ud504\ud53c\ud53d\ud558\ud559\ud55c\ud560\ud568\ud569\ud56d\ud574\ud589\ud5a5\ud5c8\ud5d8\ud600\ud604\ud615\ud638\ud639\ud63c\ud654\ud655\ud658\ud68c\ud6a8\ud6c4\ud6c8\ud6cc\ud6e8\ud750\ud754\ud758\ud76c\ud788",
            "5k": "\uac00\uac01\uac04\uac07\uac08\uac10\uac11\uac12\uac13\uac15\uac16\uac19\uac1a\uac1b\uac1c\uac1d\uac40\uac70\uac71\uac74\uac77\uac78\uac80\uac81\uac83\uac89\uac8c\uaca8\uaca9\uacac\uacb0\uacb9\uacbd\uacc4\uace0\uace1\uace4\uace7\uace8\uacf0\uacf1\uacf3\uacf5\uacfc\uad00\uad11\uad1c\uad34\uad49\uad50\uad6c\uad6d\uad70\uad73\uad75\uad76\uad7d\uad81\uad8c\uadc0\uadd3\uaddc\uade0\uadf8\uadf9\uadfc\uae00\uae01\uae08\uae09\uae0b\uae0d\uae30\uae34\uae38\uae40\uae45\uae4a\uae4c\uae4e\uae50\uae54\uae5c\uae5d\uae61\uae65\uae68\uaebc\uaebe\uaecd\uaecf\uaed1\uaed8\uaf2c\uaf2d\uaf3c\uaf3d\uaf42\uaf43\uaf49\uaf64\uafb8\uafbc\uafc0\uafc8\ub044\ub048\ub04a\ub04c\ub053\ub054\ub057\ub05d\ub07c\ub098\ub099\ub09a\ub09c\ub0a0\ub0a1\ub0a8\ub0a9\ub0ab\ub0ad\ub0ae\ub0af\ub0b1\ub0b4\ub0c4\ub0c7\ub0c9\ub0d0\ub0e5\ub108\ub109\ub10c\ub110\ub113\ub118\ub123\ub124\ub125\ub137\ub140\ub141\ub144\ub150\ub155\ub178\ub179\ub17c\ub180\ub188\ub18d\ub192\ub193\ub194\ub1cc\ub1e8\ub204\ub208\ub258\ub274\ub284\ub290\ub291\ub298\ub299\ub2a5\ub2a6\ub2ac\ub2c8\ub2d0\ub2d8\ub2e4\ub2e5\ub2e8\ub2eb\ub2ec\ub2ed\ub2ee\ub2f4\ub2f5\ub2f7\ub2f9\ub300\ub301\ub310\ub313\ub354\ub355\ub35c\ub35f\ub364\ub365\ub367\ub369\ub36e\ub370\ub378\ub3c4\ub3c5\ub3c8\ub3cc\ub3d7\ub3d9\ub3fc\ub418\ub41c\ub450\ub451\ub458\ub465\ub4a4\ub4b7\ub4dc\ub4dd\ub4e0\ub4e3\ub4e4\ub4ec\ub4ed\ub4ef\ub4f1\ub514\ub529\ub52a\ub530\ub531\ub534\ub538\ub545\ub54c\ub55c\ub5a0\ub5a1\ub5a8\ub5bc\ub610\ub611\ub69c\ub6ab\ub6b1\ub6f0\ub728\ub729\ub72f\ub730\ub73b\ub744\ub77c\ub77d\ub780\ub78c\ub78d\ub791\ub797\ub798\ub79c\ub7a8\ub7ab\ub7b5\ub7c9\ub7ec\ub7ed\ub7f0\ub7f4\ub7fc\ub7fd\ub7ff\ub801\ub807\ub808\ub809\ub80c\ub824\ub825\ub828\ub82c\ub835\ub839\ub840\ub85c\ub85d\ub860\ub86c\ub86d\ub86f\ub8cc\ub8e8\ub8e9\ub8fb\ub904\ub958\ub959\ub960\ub974\ub978\ub984\ub987\ub98e\ub9ac\ub9ad\ub9b0\ub9bc\ub9bd\ub9bf\ub9c1\ub9c8\ub9c9\ub9cc\ub9ce\ub9d0\ub9d8\ub9db\ub9dd\ub9de\ub9e1\ub9e3\ub9e4\ub9e5\ub9e8\ub9f5\ub9fa\uba38\uba39\uba3c\uba40\uba4b\uba4d\uba4e\uba54\uba58\uba69\uba70\uba74\uba78\uba85\uba87\ubaa8\ubaa9\ubaac\ubab0\ubab8\ubab9\ubabb\ubabd\ubb18\ubb34\ubb35\ubb36\ubb38\ubb3b\ubb3c\ubb44\ubb47\ubb58\ubb63\ubbf8\ubbfc\ubbff\ubc00\ubc09\ubc0c\ubc11\ubc14\ubc15\ubc16\ubc18\ubc1b\ubc1c\ubc1d\ubc1f\ubc24\ubc25\ubc29\ubc2d\ubc30\ubc31\ubc40\ubc43\ubc49\ubc84\ubc88\ubc8c\ubc94\ubc95\ubc97\ubca0\ubca4\ubca8\ubcbc\ubcbd\ubcc0\ubcc4\ubcd1\ubcd5\ubcf4\ubcf5\ubcf6\ubcf8\ubcfc\ubd07\ubd09\ubd48\ubd59\ubd80\ubd81\ubd84\ubd88\ubd89\ubd90\ubd93\ubd95\ubd99\ubdf0\ube0c\ube10\ube14\ube44\ube4c\ube54\ube57\ube5a\ube5b\ube60\ube61\ube68\ube75\ube7c\ube8f\ubea8\ubed0\ubed4\ubed7\ubf08\ubf09\ubf51\ubfcc\uc058\uc068\uc0ac\uc0ad\uc0b0\uc0b4\uc0b6\uc0bc\uc0bf\uc0c1\uc0c8\uc0c9\uc0cc\uc0dd\uc0e4\uc11c\uc11d\uc11e\uc120\uc124\uc12c\uc12d\uc12f\uc131\uc138\uc139\uc13c\uc14b\uc154\uc158\uc18c\uc18d\uc190\uc194\uc19c\uc19f\uc1a1\uc1a5\uc1c4\uc1e0\uc1fc\uc218\uc219\uc21c\uc21f\uc220\uc228\uc22b\uc22d\uc26c\uc270\uc27d\uc288\uc2a4\uc2ac\uc2b4\uc2b5\uc2b9\uc2dc\uc2dd\uc2e0\uc2e4\uc2eb\uc2ec\uc2ed\uc2ef\uc2f1\uc2f6\uc2f8\uc2f9\uc2fc\uc30d\uc369\uc370\uc379\uc384\uc3d8\uc3df\uc464\uc4f0\uc4f4\uc4f8\uc50c\uc528\uc529\uc539\uc53b\uc544\uc545\uc548\uc549\uc54a\uc54c\uc553\uc554\uc555\uc557\uc55e\uc560\uc561\uc568\uc57c\uc57d\uc580\uc584\uc587\uc591\uc595\uc598\uc5b4\uc5b5\uc5b8\uc5b9\uc5bb\uc5bc\uc5c4\uc5c5\uc5c6\uc5c7\uc5c9\uc5ca\uc5cc\uc5ce\uc5d0\uc5d4\uc5d8\uc5ec\uc5ed\uc5f0\uc5f4\uc5f7\uc5fc\uc5fd\uc5ff\uc601\uc606\uc608\uc61b\uc624\uc625\uc628\uc62c\uc637\uc639\uc640\uc644\uc655\uc660\uc678\uc67c\uc694\uc695\uc6a9\uc6b0\uc6b1\uc6b4\uc6b8\uc6c0\uc6c3\uc6c5\uc6cc\uc6d0\uc6d4\uc6e8\uc6ec\uc704\uc717\uc720\uc721\uc728\uc73c\uc73d\uc740\uc744\uc74c\uc751\uc758\uc774\uc775\uc778\uc77c\uc77d\uc783\uc784\uc785\uc787\uc788\uc78a\uc78e\uc790\uc791\uc794\uc796\uc798\uc7a0\uc7a1\uc7a3\uc7a5\uc7a6\uc7ac\uc7c1\uc800\uc801\uc804\uc808\uc80a\uc810\uc811\uc813\uc815\uc816\uc81c\uc820\uc82f\uc838\uc870\uc871\uc874\uc878\uc881\uc885\uc88b\uc88c\uc8c4\uc8fc\uc8fd\uc900\uc904\uc90c\uc90d\uc911\uc950\uc988\uc989\uc98c\uc990\uc99d\uc9c0\uc9c1\uc9c4\uc9c8\uc9d0\uc9d1\uc9d3\uc9d5\uc9d9\uc9da\uc9dc\uc9dd\uc9e7\uc9f8\uca4c\uca4d\uca50\uca54\uca5c\ucabd\ucad3\ucb48\ucb49\ucc0c\ucc0d\ucc22\ucc28\ucc29\ucc2c\ucc2e\ucc30\ucc38\ucc3b\ucc3d\ucc3e\ucc44\ucc45\ucc54\ucc98\ucc99\ucc9c\ucca0\ucca9\uccab\uccad\uccb4\uccd0\ucd08\ucd09\ucd0c\ucd1b\ucd1d\ucd2c\ucd5c\ucd94\ucd95\ucd98\ucd9c\ucda4\ucda5\ucda7\ucda9\ucde8\uce20\uce21\uce30\uce35\uce58\uce59\uce5c\uce60\uce68\uce6b\uce6d\uce74\uce78\uce7c\uce84\uce90\ucea0\ucee4\ucee8\uceec\ucef4\ucef5\ucef7\ucf00\ucf13\ucf1c\ucf54\ucf58\ucf5c\ucf64\ucf69\ucf8c\ucfe0\ud034\ud06c\ud070\ud074\ud0a4\ud0ac\ud0c0\ud0c1\ud0c4\ud0c8\ud0d1\ud0d5\ud0dc\ud0dd\ud0e4\ud130\ud131\ud134\ud138\ud145\ud14c\ud14d\ud154\ud15c\ud1a0\ud1a4\ud1a8\ud1b1\ud1b5\ud1f4\ud22c\ud234\ud23c\ud241\ud280\ud29c\ud2b8\ud2b9\ud2bc\ud2bf\ud2c0\ud2c8\ud2f0\ud2f1\ud305\ud30c\ud30e\ud310\ud314\ud31d\ud328\ud329\ud32c\ud37c\ud37d\ud398\ud39c\ud3b4\ud3b8\ud3bc\ud3c9\ud3d0\ud3ec\ud3ed\ud3f0\ud45c\ud478\ud479\ud480\ud488\ud48d\ud504\ud50c\ud514\ud53c\ud53d\ud544\ud54f\ud551\ud558\ud559\ud55c\ud560\ud568\ud569\ud56d\ud574\ud575\ud578\ud584\ud587\ud589\ud5a5\ud5c8\ud5cc\ud5d8\ud5e4\ud5ec\ud600\ud604\ud608\ud611\ud615\ud61c\ud638\ud639\ud63c\ud640\ud648\ud649\ud64d\ud654\ud655\ud658\ud65c\ud669\ud68c\ud68d\ud69f\ud6a1\ud6a8\ud6c4\ud6c8\ud6d4\ud718\ud734\ud749\ud750\ud751\ud754\ud758\ud759\ud761\ud765\ud769\ud76c\ud770\ud788\ud798"
        },
        "limits": {
            "basic": {
                "plain": 470
            },
            "1k": {
                "plain": 975
            },
            "5k": {
                "plain": 4201
            }
        }
    },
    "ne": {
        "name": "Nepali",
        "sentenceCode": "npi",
        "dictionarySHA": "c5a83fae6720d60ef9107c55e993e7bfe6f67e991a2b82633375f60a064c9a0f",
        "sentencesSHA": "cfb9e1b2f990f6eb12d4395451dfba44729fef092690e10ffdb0c8f588c051c2",
        "extraction": "2026-10-21; enwiktionary dump 2026-10-01; c1bb342 / 6f96ddf",
        "legacy": [
            "\u0915\u093f\u0924\u093e\u092c",
            "\u0915\u0932\u092e",
            "\u091d\u094d\u092f\u093e\u0932",
            "\u092c\u093e\u091f\u094b",
            "\u0909\u091c\u094d\u092f\u093e\u0932\u094b",
            "\u092a\u0941\u0932",
            "\u092c\u093f\u0939\u093e\u0928",
            "\u0915\u093e\u0917\u091c",
            "\u092c\u0917\u0948\u0901\u091a\u093e",
            "\u092c\u093e\u0926\u0932",
            "\u0936\u093e\u0928\u094d\u0924\u093f",
            "\u0926\u093f\u092f\u094b",
            "\u092a\u0939\u093e\u0921",
            "\u092c\u0940\u0909",
            "\u0938\u0919\u094d\u0917\u0940\u0924",
            "\u091f\u0947\u092c\u0932",
            "\u0935\u093f\u091a\u093e\u0930",
            "\u091f\u093f\u092a\u094b\u091f",
            "\u0915\u0932\u094d\u092a\u0928\u093e",
            "\u092a\u094d\u0930\u092f\u093e\u0938",
            "\u0926\u0942\u0930\u0940",
            "\u0915\u0926\u092e",
            "\u0927\u0948\u0930\u094d\u092f",
            "\u0938\u0928\u094d\u0924\u0941\u0932\u0928"
        ],
        "pools": {
            "basic": [
                200,
                1,
                10
            ],
            "1k": [
                1000,
                1,
                11
            ]
        },
        "referenceKeys": {
            "basic": "\u0901\u0902\u0905\u0906\u0907\u0908\u0909\u090f\u0913\u0915\u0916\u0917\u0918\u091a\u091b\u091c\u091d\u091f\u0920\u0921\u0922\u0923\u0924\u0925\u0926\u0927\u0928\u092a\u092b\u092c\u092d\u092e\u092f\u0930\u0932\u0935\u0936\u0937\u0938\u0939\u093e\u093f\u0940\u0941\u0942\u0943\u0947\u0948\u094b\u094c\u094d",
            "1k": "\u0901\u0902\u0905\u0906\u0907\u0908\u0909\u090a\u090f\u0910\u0913\u0914\u0915\u0916\u0917\u0918\u0919\u091a\u091b\u091c\u091d\u091e\u091f\u0920\u0921\u0922\u0923\u0924\u0925\u0926\u0927\u0928\u092a\u092b\u092c\u092d\u092e\u092f\u0930\u0932\u0935\u0936\u0937\u0938\u0939\u093e\u093f\u0940\u0941\u0942\u0943\u0947\u0948\u094b\u094c\u094d"
        },
        "limits": {
            "basic": {
                "plain": 18,
                "mark": 182
            },
            "1k": {
                "plain": 73,
                "mark": 927
            }
        }
    }
}
WHEEL_SHA = '4b1c6ecffc6198be3396d5cf871c4423ca71c907c231348d352dd54d62b97473'
MEMBER = 'wordfreq/data/small_ko.msgpack.gz'
MEMBER_SHA = '01014287a9e779d232f965d054a9cb5eb10b0bc46ee464fbd42935a5df7c8319'
ALLOWED_KEYS = {code: set(''.join(spec['referenceKeys'].values()) + ''.join(spec['legacy'])) for code, spec in SPECS.items()}
MAX_UNITS = {code: max(v[2] for v in spec['pools'].values()) for code, spec in SPECS.items()}
PUBLISHED = {'Compatibility/korean-corpus.json': 'a5e1e65d17cd4b18b40a8e1e9325995ae390d34378115fed023e4097a95ccb48', 'Compatibility/nepali-corpus.json': '65dac9282c4a953b7e1ca15212fad80aac575b255efde5834d80e114475ab9f5', 'Resources/KoreanCorpusNotices.txt': '2bebf3ac48692097d2ec467e1804cfd43ff4351980bd9662b883ff1c124b4a53', 'Resources/KoreanCorpusSources.txt': 'd80bb4c6fa980ad34937815263eac40484a779affe170e4186e6a3fef0f28ac1', 'Resources/NepaliCorpusNotices.txt': 'c80ab7841f43e81a021da4eea27900ed826e85cafa003746b0de99a6796c3e39', 'Resources/NepaliCorpusSources.txt': '1f72cceda9b4bae603c831184affd19e1dc9e4211366fe90e04e6d20eb418738', 'Sources/Typebar/KoreanCorpus.generated.swift': '7a44e755261134b49478316b27bb8e2ad40e7c5b263dd696f2f2a3ea1404540b', 'Sources/Typebar/NepaliCorpus.generated.swift': '8f143a70352d3891ac6b05767b49b32004e9f7743b3bfe3a15981e61cffcdfcc'}



def require(value, message):
    if not value:
        raise ValueError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def paths(code):
    name = SPECS[code]['name']
    return ('Sources/Typebar/' + name + 'Corpus.generated.swift',
            'Resources/' + name + 'CorpusSources.txt',
            'Resources/' + name + 'CorpusNotices.txt',
            'Compatibility/' + name.lower() + '-corpus.json')


def literal(word, code):
    spec = SPECS[code]
    keys = ALLOWED_KEYS[code]
    if not (type(word) is str and word and len(word) <= MAX_UNITS[code]
            and word == unicodedata.normalize('NFC', word) and set(word) <= keys):
        return False
    if code == 'ko':
        return all(0xAC00 <= ord(c) <= 0xD7A3 for c in word)
    return word[0].isalpha() and all(c.isalpha() or unicodedata.category(c).startswith('M') for c in word)


def category(word, code):
    return 'mark' if code == 'ne' and any(unicodedata.category(c).startswith('M') for c in word) else 'plain'


def collect(entry, code, forms):
    require(type(entry) is dict, 'invalid entry')
    if entry.get('lang_code') != code or entry.get('pos') not in PARTS:
        return
    senses = entry.get('senses', [])
    require(type(senses) is list and all(type(v) is dict for v in senses), 'invalid senses')
    if not senses or all(BAD.intersection(v.get('tags', [])) for v in senses):
        return
    title = entry.get('word')
    require(type(title) is str and not any(c in title for c in '\t\r\n'), 'invalid title')
    rows = entry.get('forms', [])
    require(type(rows) is list, 'invalid forms')
    for row in [{'form': title}] + rows:
        require(type(row) is dict and type(row.get('form')) is str, 'invalid form')
        tags = row.get('tags', [])
        require(type(tags) is list and all(type(t) is str for t in tags), 'invalid tags')
        if BAD.intersection(tags) or any(t in {'romanization', 'table-tags', 'inflection-template', 'class'} or t.startswith('error-') for t in tags):
            continue
        word = row['form']
        if literal(word, code):
            forms.setdefault(word, ('dictionary', title, word, 'none', title))


def read_frequency(wheel):
    require(sha(wheel.read_bytes()) == WHEEL_SHA, 'wordfreq wheel pin mismatch')
    import msgpack
    require(msgpack.__version__ == '1.1.2', 'requires msgpack 1.1.2')
    with zipfile.ZipFile(wheel) as archive:
        member = archive.read(MEMBER)
        metadata = archive.read('wordfreq-3.1.1.dist-info/METADATA').decode()
    require(sha(member) == MEMBER_SHA, 'wordfreq member pin mismatch')
    bins = msgpack.unpackb(gzip.decompress(member), raw=False)
    require(bins[0] == {'format': 'cB', 'version': 1}, 'invalid frequency format')
    bands = {}
    for index, words in enumerate(bins[1:]):
        require(type(words) is list and words == sorted(set(words)), 'invalid frequency bin')
        for word in words:
            require(type(word) is str and word not in bands, 'invalid frequency token')
            bands[word] = index
    require(len(bands) == 29988, 'unexpected Korean observation count')
    return bands, metadata[metadata.index('## License'):].strip() + '\n'


def tokens(text):
    text = unicodedata.normalize('NFC', text)
    start = None
    for index, c in enumerate(text):
        inside = c.isalnum() or c in "_-'’" or unicodedata.category(c)[0] in {'M', 'C'}
        if inside and start is None:
            start = index
        elif not inside and start is not None:
            yield text[start:index]; start = None
    if start is not None:
        yield text[start:]


def read_sources(code, dictionary, sentences, wheel):
    spec = SPECS[code]
    require(sha(dictionary.read_bytes()) == spec['dictionarySHA'], 'dictionary pin mismatch')
    forms = {}
    for line in dictionary.open(encoding='utf-8'):
        collect(json.loads(line), code, forms)
    bands, license_text = read_frequency(wheel) if code == 'ko' else ({}, '')
    for word in bands:
        if literal(word, code):
            forms.setdefault(word, ('wordfreq', 'wordfreq 3.1.1 / ' + MEMBER, word, 'none', 'NA'))
    for word in spec['legacy']:
        forms.setdefault(word, ('typebar-legacy', 'Typebar authored starter vocabulary', word, 'none', 'NA'))
    require(sha(sentences.read_bytes()) == spec['sentencesSHA'], 'sentence pin mismatch')
    counts, first, authors, identifiers = Counter(), {}, set(), set()
    for line in bz2.open(sentences, 'rt', encoding='utf-8'):
        fields = line.rstrip('\n').split('\t')
        require(len(fields) == 6 and fields[0].isdigit() and fields[1] == spec['sentenceCode'], 'invalid sentence')
        identifier, _, text, author, _, _ = fields
        require(identifier not in identifiers, 'duplicate sentence')
        identifiers.add(identifier)
        author = author if author not in {'', '\\N'} else '(unowned)'
        authors.add(author)
        for word in {w for w in tokens(text) if w in forms}:
            counts[word] += 1
            first.setdefault(word, (identifier, author))
    return forms, counts, first, sorted(authors), len(identifiers), bands, license_text


def grapheme_counts(forms, node):
    words = sorted(forms)
    program = """const fs=require('node:fs');
if(process.version!=='v24.19.0'||process.versions.unicode!=='17.0')throw Error('Pinned Node v24.19.0 / Unicode 17.0 required');
const words=JSON.parse(fs.readFileSync(0,'utf8'));
const segmenter=new Intl.Segmenter('ne',{granularity:'grapheme'});
process.stdout.write(JSON.stringify(words.map(w=>[...segmenter.segment(w)].length)));"""
    result = subprocess.run([str(node), '-e', program], input=json.dumps(words, ensure_ascii=False), text=True, capture_output=True)
    require(result.returncode == 0, 'grapheme runtime failed: ' + result.stderr)
    counts = json.loads(result.stdout)
    require(type(counts) is list and len(counts) == len(words) and all(type(n) is int and 1 <= n <= len(w) for w, n in zip(words, counts)), 'invalid grapheme counts')
    return dict(zip(words, counts))


def select(code, forms, counts, bands, graphemes):
    spec = SPECS[code]
    def rank(word):
        kind, title, raw, _, _ = forms[word]
        if code == 'ko':
            return (word not in bands, bands.get(word, 0), raw != title, word)
        return (word not in counts, -counts.get(word, 0), raw != title, word)
    pools = {}
    for name, (count, minimum, maximum) in spec['pools'].items():
        keys = set(spec['referenceKeys'][name] + ''.join(spec['legacy']))
        limits = spec['limits'][name]
        eligible = {w for w in forms if literal(w, code) and set(w) <= keys and minimum <= len(w) <= maximum
                    and (code != 'ne' or graphemes[w] <= (5 if name == 'basic' else 6))}
        # Korean source alphabets differ; do not force new basic vocabulary into scales.
        chosen = set(spec['legacy']) | (set(pools.get('basic', [])) if code == 'ne' else set())
        require(chosen <= eligible, 'missing old vocabulary or incompatible seed')
        used = Counter(category(w, code) for w in chosen)
        def add_best(options, key=rank):
            word = min((w for w in options if w not in chosen and used[category(w, code)] < limits.get(category(w, code), 0)), key=key, default=None)
            require(word is not None, 'insufficient coverage: ' + code + '/' + name)
            chosen.add(word); used[category(word, code)] += 1
        for length in [minimum, maximum]:
            if not any(len(w) == length for w in chosen):
                add_best(w for w in eligible if len(w) == length)
        if code == 'ne':
            maximum_graphemes = 5 if name == 'basic' else 6
            if not any(graphemes[w] == maximum_graphemes for w in chosen):
                add_best(w for w in eligible if graphemes[w] == maximum_graphemes)
        missing = keys - set(''.join(chosen))
        # Lazy greedy coverage keeps the same gain/rank ordering as repeated
        # global min(), while avoiding rescanning every literal for each syllable.
        coverage = []
        for word in eligible - chosen:
            characters = frozenset(word)
            gain = len(characters & missing)
            if gain:
                coverage.append((-gain, rank(word), word, characters))
        heapq.heapify(coverage)
        while missing:
            found = False
            while coverage:
                negative, priority, word, characters = heapq.heappop(coverage)
                key = category(word, code)
                if used[key] >= limits.get(key, 0):
                    continue
                gain = len(characters & missing)
                if not gain:
                    continue
                if gain != -negative:
                    heapq.heappush(coverage, (-gain, priority, word, characters))
                    continue
                chosen.add(word); used[key] += 1
                missing.difference_update(characters)
                found = True
                break
            require(found, 'insufficient coverage: ' + code + '/' + name)
        for key, limit in limits.items():
            require(used[key] <= limit, 'seed exceeds quota')
            options = sorted((w for w in eligible if w not in chosen and category(w, code) == key), key=rank)
            needed = limit - used[key]
            require(len(options) >= needed, 'insufficient category')
            chosen.update(options[:needed])
        require(len(chosen) == count and dict(Counter(category(w, code) for w in chosen)) == limits, 'quota mismatch')
        require(set(''.join(chosen)) == keys, 'typing key mismatch')
        pools[name] = sorted(chosen, key=rank)
    return pools


def artifacts(code, dictionary, sentences, wheel, node):
    spec = SPECS[code]
    forms, counts, first, authors, sentence_count, bands, license_text = read_sources(code, dictionary, sentences, wheel)
    graphemes = grapheme_counts(forms, node) if code == 'ne' else {w: len(w) for w in forms}
    pools = select(code, forms, counts, bands, graphemes)
    swift, source_map, notice_path, manifest_path = paths(code)
    revision = 'kaikki-' + code + '-20261103-literal-v1'
    native = '// Independent literal corpus; see bundled provenance and licenses.\nenum ' + spec['name'] + 'Corpus {\n  static let revision = ' + json.dumps(revision) + '\n'
    for name, words in pools.items():
        native += '  static let ' + ('basic' if name == 'basic' else 'words' + name) + ': [String] = """\n' + '\n'.join(words) + '\n""".split(separator: "\\n").map(String.init)\n'
    native += '}\n'
    union = sorted(set().union(*map(set, pools.values())))
    rows = '# word\tsourceKind\tsourceTitle\tsourceForm\tadaptation\tlexicalWitnessTitle\twordfreqWholeTokenBand\tobservationMode\twholeTokenSentenceCount\tfirstSentenceID\tfirstSentenceAuthor (NA means unobserved)\n'
    for word in union:
        identifier, author = first.get(word, ('NA', 'NA'))
        rows += '\t'.join([word, *forms[word], str(bands[word]) if word in bands else 'NA', 'NFC-whole-token', str(counts[word]) if word in counts else 'NA', identifier, author]) + '\n'
    unattested = sorted(w for w in spec['legacy'] if forms[w][0] == 'typebar-legacy')
    extras = {n: ''.join(sorted(set(''.join(spec['legacy'])) - set(spec['referenceKeys'][n]))) for n in pools}
    dictionary_url = 'https://kaikki.org/dictionary/' + spec['name'] + '/kaikki.org-dictionary-' + spec['name'] + '.jsonl'
    sentence_url = 'https://downloads.tatoeba.org/exports/per_language/' + spec['sentenceCode'] + '/' + spec['sentenceCode'] + '_sentences_detailed.tsv.bz2'
    frequency_notice = (f"""wordfreq 3.1.1: https://pypi.org/project/wordfreq/3.1.1/
Wheel SHA-256: {WHEEL_SHA}
Member: {MEMBER}; SHA-256: {MEMBER_SHA}
29988 observed whole tokens; individual missing observations are NA, never zero.
Literal standalone frequency tokens may supply syllables absent from selected
dictionary entries. Such options are marked wordfreq, never dictionary forms.
Bands determine ranking, not runtime Zipf support or token usage counts.
The complete upstream metadata license section follows contributor credits.
""" if code == 'ko' else 'No wordfreq dataset is used for Nepali.\n')
    notice = f"""Typebar independent {spec['name']} corpus
Revision: {revision}
English Wiktionary contributors via Kaikki.org / Wiktextract.
Dictionary: {dictionary_url}
Snapshot SHA-256: {spec['dictionarySHA']}
Index reports: {spec['extraction']}.
Dictionary selection: CC BY-SA 4.0 International.
https://creativecommons.org/licenses/by-sa/4.0/
Dictionary contributor pages: https://en.wiktionary.org/wiki/ + encoded sourceTitle.
Only literal NFC lexical titles/forms of lang_code={code} are selected.
Nonstandard/proscribed/misspelling-only senses and tagged romanization,
template/error forms are excluded. No spelling synthesis, artificial casing,
numbered padding or original Monkeytype words, code or assets are bundled.
All 24 old Typebar starters remain in every pool. Selected lexical attestation
missing for: {', '.join(unattested) or '(none)'}.
This reports allowed lexical categories, not absence of other raw entries.
Legacy extra character sets by pool: {json.dumps(extras, ensure_ascii=False, sort_keys=True)}.
These retain previously available typing content; no other new keys are added.
Korean pools are independently selected: their source alphabets are not nested.
Nepali basic vocabulary is retained in its 1k pool. Length is source UTF-16
units, distinct from Swift graphemes for Devanagari. Pinned Node v24.19.0 /
Unicode 17.0 segmentation limits Nepali graphemes to 5 basic / 6 in 1k;
native Swift tests independently check those selected-word limits. Mark-only strings are
rejected; every option starts with a letter. No old-word length exceptions.
Per-word provenance: {source_map.split('/')[-1]}; unchanged source form and
source kind distinguish dictionary, frequency-only and authored legacy data.
{frequency_notice}
Tatoeba {spec['name']} contributors: CC BY 2.0 France.
Sentences: {sentence_url}
Snapshot SHA-256: {spec['sentencesSHA']}
Sentence rows: {sentence_count}; contributor identifiers: {len(authors)}.
https://creativecommons.org/licenses/by/2.0/fr/
https://tatoeba.org/en/downloads
Sentence data is used for whole-token observations only; no sentence text,
translations or audio is bundled. Token matching uses NFC and retains digits,
underscores, hyphens, apostrophes, marks and controls/format characters inside
token boundaries to reject partial-word matches. One match per sentence;
missing observations remain NA, never zero or component-frequency estimates.
Nepali exports use npi, not the unavailable nep archive.
Vocabulary quality, representative frequency distribution and physical input
are not certified equivalent to Monkeytype. Runtime Zipf support is unchanged.
All processed contributor identifiers follow; unknown/unowned rows are explicit.

""" + '\n'.join(a if a == '(unowned)' else a + ' https://tatoeba.org/en/user/profile/' + quote(a, safe='') for a in authors) + '\n\n' + license_text
    notice = notice.rstrip() + '\n'
    output = {swift: native.encode(), source_map: rows.encode(), notice_path: notice.encode()}
    doc = {'schemaVersion': 1, 'revision': revision, 'dictionary': dictionary_url, 'dictionarySHA256': spec['dictionarySHA'], 'sentences': sentence_url, 'sentencesSHA256': spec['sentencesSHA'], 'sentenceRows': sentence_count, 'contributorIdentifiers': len(authors), 'legacyUnattested': unattested, 'frequencyWheelSHA256': WHEEL_SHA if code == 'ko' else None, 'frequencyMember': MEMBER if code == 'ko' else None, 'frequencyMemberSHA256': MEMBER_SHA if code == 'ko' else None, 'artifacts': {n: sha(b) for n, b in output.items()}, 'pools': {}}
    for name, words in pools.items():
        doc['pools'][name] = {'count': len(words), 'minimumUTF16Length': min(map(len, words)), 'minimumGraphemeCount': min(graphemes[w] for w in words), 'maximumGraphemeCount': max(graphemes[w] for w in words), 'maximumUTF16Length': max(map(len, words)), 'characters': ''.join(sorted(set(''.join(words)))), 'referenceCharacters': spec['referenceKeys'][name], 'legacyExtraCharacters': extras[name], 'categories': dict(Counter(category(w, code) for w in words)), 'sentenceObserved': sum(w in counts for w in words), 'wordfreqObserved': sum(w in bands for w in words), 'sourceKinds': dict(Counter(forms[w][0] for w in words)), 'wordsSHA256': sha(('\n'.join(words) + '\n').encode())}
    output[manifest_path] = (json.dumps(doc, ensure_ascii=False, sort_keys=True, indent=2) + '\n').encode()
    return output


def verify_bundled(root):
    require(len(PUBLISHED) == 8, 'eight immutable pins required')
    for name, digest in PUBLISHED.items():
        require(sha((root / name).read_bytes()) == digest, 'published pin mismatch: ' + name)
    for code, spec in SPECS.items():
        swift, rows_path, _, manifest = paths(code)
        pools = {('basic' if n == 'basic' else n[5:]): s.splitlines() for n, s in re.findall(r'static let (basic|words1k|words5k): \[String\] = """\n(.*?)\n"""', (root / swift).read_text(), re.S)}
        require(list(pools) == list(spec['pools']), 'missing native pools')
        rows = [s.split('\t') for s in (root / rows_path).read_text().splitlines() if not s.startswith('#')]
        require(all(len(r) == 11 for r in rows), 'invalid field count')
        provenance = {r[0]: r for r in rows}
        require(len(rows) == len(provenance) and set(provenance) == set().union(*map(set, pools.values())), 'missing provenance')
        for row in rows:
            require(row[1] in {'dictionary', 'wordfreq', 'typebar-legacy'} and row[2] and row[0] == row[3] and row[4] == 'none' and row[7] == 'NFC-whole-token', 'invalid source identity')
            require(row[6] == 'NA' or row[6].isdigit(), 'invalid band')
            require(row[8:] == ['NA', 'NA', 'NA'] or row[8].isdigit() and int(row[8]) > 0 and row[9].isdigit() and row[10], 'invalid observation')
            if row[1] == 'wordfreq':
                require(code == 'ko' and row[6] != 'NA' and row[5] == 'NA', 'false frequency source')
        doc = json.loads((root / manifest).read_text())
        for name, words in pools.items():
            count, minimum, maximum = spec['pools'][name]
            require(len(words) == len(set(words)) == count and set(spec['legacy']) <= set(words), 'count/retention mismatch')
            if code == 'ne':
                require(set(pools['basic']) <= set(words), 'Nepali basic retention mismatch')
            require(set(''.join(words)) == set(spec['referenceKeys'][name] + ''.join(spec['legacy'])), 'alphabet mismatch')
            require(all(literal(w, code) and minimum <= len(w) <= maximum for w in words) and min(map(len, words)) == minimum and max(map(len, words)) == maximum, 'literal/length mismatch')
            require(dict(Counter(category(w, code) for w in words)) == spec['limits'][name], 'category mismatch')
            require(doc['pools'][name]['wordsSHA256'] == sha(('\n'.join(words) + '\n').encode()), 'word pin mismatch')
            require(doc['pools'][name]['sentenceObserved'] == sum(provenance[w][8] != 'NA' for w in words), 'sentence count mismatch')
            require(doc['pools'][name]['wordfreqObserved'] == sum(provenance[w][6] != 'NA' for w in words), 'frequency observation mismatch')


class ContractTests(unittest.TestCase):
    def test_literal_hangul_and_devanagari_are_not_synthetic_marks(self):
        self.assertTrue(literal('안팎', 'ko'))
        self.assertFalse(literal('힣', 'ko'))
        self.assertFalse(literal('가', 'ko'))
        self.assertTrue(literal('किताब', 'ne'))
        self.assertFalse(literal('ि', 'ne'))
        self.assertFalse(literal('िक', 'ne'))
        self.assertEqual(category('कि', 'ne'), 'mark')
        self.assertEqual(category('घर', 'ne'), 'plain')

    def test_dictionary_filter_keeps_exact_form_and_rejects_romanization(self):
        f = {}
        collect({'lang_code': 'ko', 'pos': 'noun', 'word': '기억', 'senses': [{}], 'forms': [{'form': 'giek', 'tags': ['romanization']}]}, 'ko', f)
        self.assertEqual(f, {'기억': ('dictionary', '기억', '기억', 'none', '기억')})
        collect({'lang_code': 'ne', 'pos': 'noun', 'word': 'घर', 'senses': [{'tags': ['misspelling']}]}, 'ne', f)
        self.assertNotIn('घर', f)

    def test_token_boundaries_keep_vowel_signs_virama_and_controls(self):
        self.assertEqual(list(tokens('किताब घर, 안팎!')), ['किताब', 'घर', '안팎'])
        for text in ['घर-घर', "घर'घर", 'घर_2', 'घर\u200dघर', 'घर\u0301']:
            self.assertNotIn('घर', list(tokens(text)))



def main():
    p = argparse.ArgumentParser(description=__doc__)
    for code in SPECS:
        p.add_argument('--' + code + '-dictionary', type=Path)
        p.add_argument('--' + code + '-sentences', type=Path)
    p.add_argument('--wordfreq-wheel', type=Path)
    p.add_argument('--grapheme-node', type=Path)
    p.add_argument('--output', type=Path); p.add_argument('--check', action='store_true')
    p.add_argument('--self-test', action='store_true'); p.add_argument('--check-bundled', action='store_true')
    args = p.parse_args()
    if args.self_test:
        raise SystemExit(not unittest.TextTestRunner().run(unittest.defaultTestLoader.loadTestsFromTestCase(ContractTests)).wasSuccessful())
    if args.check_bundled:
        verify_bundled(ROOT); print('Korean/Nepali pinned corpus/provenance check passed'); return
    require(args.output is not None and args.wordfreq_wheel and args.grapheme_node, 'output, wordfreq wheel and pinned grapheme node required')
    output = {}
    for code in SPECS:
        dictionary, sentences = getattr(args, code + '_dictionary'), getattr(args, code + '_sentences')
        require(dictionary and sentences, 'both dictionary and sentence snapshots required')
        output.update(artifacts(code, dictionary, sentences, args.wordfreq_wheel, args.grapheme_node))
    if PUBLISHED:
        require({n: sha(b) for n, b in output.items()} == PUBLISHED, 'reproduction pins mismatch')
    for name, data in output.items():
        path = args.output / name
        if args.check:
            require(path.read_bytes() == data, 'source reproduction mismatch: ' + name)
        else:
            require(not path.exists(), 'refusing to overwrite: ' + name)
            path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(data)
    print('Korean/Nepali source reproduction checked' if args.check else 'Korean/Nepali corpora prepared')


if __name__ == '__main__':
    main()
