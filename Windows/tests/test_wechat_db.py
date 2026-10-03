import unittest

from assistant.core import BusySession, Snapshot
from assistant.wechat import WeChatError
from assistant.wechat_db import resolve_contact, rows_to_messages


class FakeDB:
    wxid = "wxid_self"

    def __init__(self, rows):
        self.rows = rows

    def search_contact(self, _):
        return self.rows


def row(seq, sender, text, kind="文本"):
    return {"sort_seq": seq, "local_id": seq, "create_time": seq,
            "sender_id": sender, "type": kind, "content": text}


class DatabaseAdapterTests(unittest.TestCase):
    def test_filehelper_is_allowed_only_without_name_collision(self):
        db = FakeDB([])
        self.assertEqual(resolve_contact(db, "文件传输助手"), "filehelper")
        db.rows.append({"username": "wxid_other", "remark": "文件传输助手", "nick_name": "其他人"})
        with self.assertRaises(WeChatError):
            resolve_contact(db, "文件传输助手")

    def test_contact_must_resolve_to_one_person(self):
        db = FakeDB([
            {"username": "wxid_friend", "remark": "朋友", "nick_name": "原名"},
            {"username": "group@chatroom", "remark": "其他群", "nick_name": "其他群"},
        ])
        self.assertEqual(resolve_contact(db, "朋友"), "wxid_friend")
        db.rows.append({"username": "wxid_other", "remark": "朋友", "nick_name": "另一人"})
        with self.assertRaises(WeChatError):
            resolve_contact(db, "朋友")
        db.rows.pop()
        db.rows[1]["remark"] = "朋友"
        with self.assertRaises(WeChatError):
            resolve_contact(db, "朋友")

    def test_same_text_has_distinct_database_identity(self):
        older = rows_to_messages([row(1, 3, "你好")])
        newer = rows_to_messages([row(2, 3, "你好"), row(1, 3, "你好")])
        session = BusySession("朋友", 5, 2)
        session.observe(Snapshot("朋友", older, "", True))
        candidate = session.observe(Snapshot("朋友", newer, "", True))
        self.assertIsNotNone(candidate)
        self.assertEqual(candidate.incoming, "你好")

    def test_media_does_not_become_ai_prompt_and_sent_row_is_verified(self):
        older = rows_to_messages([row(1, 3, "旧消息")])
        media = rows_to_messages([row(2, 3, "[图片]", "图片"), row(1, 3, "旧消息")])
        text = rows_to_messages([row(3, 3, "新消息"), row(2, 3, "[图片]", "图片"), row(1, 3, "旧消息")])
        sent = rows_to_messages([row(4, 2, "收到"), row(3, 3, "新消息"),
                                 row(2, 3, "[图片]", "图片"), row(1, 3, "旧消息")])
        session = BusySession("朋友", 5, 2)
        session.observe(Snapshot("朋友", older, "", True))
        self.assertIsNone(session.observe(Snapshot("朋友", media, "", True)))
        self.assertEqual(session.observe(Snapshot("朋友", text, "", True)).incoming, "新消息")
        self.assertTrue(session.sent_reply(Snapshot("朋友", sent, "", True), "收到"))


if __name__ == "__main__":
    unittest.main()
