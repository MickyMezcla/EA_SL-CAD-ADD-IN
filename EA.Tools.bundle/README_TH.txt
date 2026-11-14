EA Tools 1.0.5 สำหรับ AutoCAD 2021 (Windows)

แท็บ EA Tools มีสองหมวด
PROKON: Points to PROKON, Cover to Bar Points, Wall Shape to PROKON และ Arc Wall Shape to PROKON
Column: Draw Column, Draw C-Link และ Points to Rebar

Points to PROKON: หลังเลือก POINT หรือ CIRCLE ให้กด Enter เพื่อใช้ CAD WCS 0,0
หรือคลิกจุดในแบบเพื่อให้เป็น 0,0 ของ PROKON คำสั่งจะเลื่อนเฉพาะพิกัดส่งออก

Points to Rebar (POINTS2REBAR): ลากคลุม POINT แล้วกด Enter จากนั้นใส่ขนาดเหล็ก
เป็นเส้นผ่านศูนย์กลาง (ค่าเริ่มต้น 16 มม.) โปรแกรมสร้าง CIRCLE และ SOLID HATCH
สีขาวบนเลเยอร์ EA-REBAR-SYMBOLS โดยเก็บ POINT ต้นฉบับไว้
ตอนส่ง PROKON ให้ซ่อนเลเยอร์ EA-REBAR-SYMBOLS ก่อนเลือก POINT เพื่อไม่ส่งวงกลมซ้ำ

Cover to Bar Points: เลือก Corewall หลังกรอกขนาดเหล็กและ spacing
เลือกเฉพาะเส้น Cover รอบนอกและรอบช่องเปิดทั้งหมดใน Selection เดียว
แล้วกด Enter โปรแกรมจะแยกกรอบนอกและช่องเปิดเพื่อหา Offset เอง
อย่ารวมเส้นขอบคอนกรีตหรือเส้นแนวเหล็กที่สร้างไว้ก่อนหน้า
หรือเลือกเส้น Cover รอบนอกวงเดียว กรอกระยะ Cover จริง (ตัวอย่าง 40 มม.)
โปรแกรมจะหาคู่ขอบคอนกรีตกับเส้น Cover ของช่องเปิดตามระยะนั้น
ตรวจวงที่ไฮไลต์และจำนวนช่องเปิดก่อนตอบ Yes หากผนังมี Cover หลายค่า
หรือไม่มีคู่เส้นขอบคอนกรีต ให้เลือกเส้น Cover ทุกวงเอง
รองรับวงปิดแนว X/Y ที่ Z=0 ไม่มีโค้งหรือความกว้างเส้น
จับคู่หน้าผนังจากระยะศูนย์เหล็กสองหน้าไม่เกิน 1,000 มม.
ใช้กติกาการแบ่ง spacing เดิม ตรวจรายละเอียดมุมและทางแยกก่อนส่งออก
เลือก Single เพื่อใช้วิธีเดิมสำหรับเส้นเดี่ยวและเส้นโค้ง

ติดตั้ง: ปิด AutoCAD และย้าย PROKONTools.bundle กับ ColumnTools.bundle เดิมออกจาก
ApplicationPlugins เพื่อเก็บสำรอง จากนั้นคัดลอก EA.Tools.bundle เข้าไปใน
%APPDATA%\Autodesk\ApplicationPlugins\ แล้วเปิด AutoCAD ใหม่
