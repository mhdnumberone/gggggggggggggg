# directory_api.py - API for directory tree structure

import os
import json
import datetime
import logging
from flask import jsonify, request

# Logging Setup
logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(name)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger("DirectoryAPI")

def register_directory_routes(app):
    """
    Register directory API routes with the Flask app
    """
    @app.route("/api/directory", methods=["GET"])
    def get_directory_contents():
        """
        Get contents of a directory as a tree structure
        Query parameters:
        - path: Path to the directory (default: root data directory)
        """
        try:
            # Get the base data directory from the app
            base_dir = app.config.get("DATA_RECEIVED_DIR", os.path.abspath("./received_data"))
            
            # Get the requested path from query parameters
            requested_path = request.args.get("path", "")
            
            # Ensure the path is within the base directory for security
            if requested_path:
                # Normalize the path to prevent directory traversal attacks
                full_path = os.path.normpath(os.path.join(base_dir, requested_path))
                
                # Ensure the path is within the base directory
                if not full_path.startswith(base_dir):
                    logger.warning(f"Attempted directory traversal: {requested_path}")
                    return jsonify({
                        "status": "error",
                        "message": "Invalid directory path"
                    }), 403
            else:
                full_path = base_dir
            
            # Check if the path exists and is a directory
            if not os.path.exists(full_path):
                logger.warning(f"Path does not exist: {full_path}")
                return jsonify({
                    "status": "error",
                    "message": "Directory not found"
                }), 404
            
            if not os.path.isdir(full_path):
                logger.warning(f"Path is not a directory: {full_path}")
                return jsonify({
                    "status": "error",
                    "message": "Path is not a directory"
                }), 400
            
            # Get the directory contents
            items = []
            for item in os.listdir(full_path):
                item_path = os.path.join(full_path, item)
                item_stat = os.stat(item_path)
                item_type = "directory" if os.path.isdir(item_path) else "file"
                
                # Calculate relative path from base directory
                rel_path = os.path.relpath(item_path, base_dir)
                
                # Format modification time
                mod_time = datetime.datetime.fromtimestamp(item_stat.st_mtime).isoformat()
                
                items.append({
                    "name": item,
                    "type": item_type,
                    "path": rel_path,
                    "size": item_stat.st_size if item_type == "file" else None,
                    "modified": mod_time
                })
            
            # Sort items: directories first, then files, both alphabetically
            items.sort(key=lambda x: (0 if x["type"] == "directory" else 1, x["name"].lower()))
            
            # Calculate relative path from base directory for the current directory
            rel_current_path = os.path.relpath(full_path, base_dir)
            if rel_current_path == ".":
                rel_current_path = ""
            
            return jsonify({
                "status": "success",
                "path": rel_current_path,
                "items": items
            }), 200
            
        except Exception as e:
            logger.error(f"Error in get_directory_contents: {e}", exc_info=True)
            return jsonify({
                "status": "error",
                "message": f"Server error: {str(e)}"
            }), 500
    
    @app.route("/api/directory/create", methods=["POST"])
    def create_directory():
        """
        Create a new directory
        JSON body parameters:
        - path: Parent directory path
        - name: Name of the new directory
        """
        try:
            # Get the base data directory from the app
            base_dir = app.config.get("DATA_RECEIVED_DIR", os.path.abspath("./received_data"))
            
            # Get request data
            data = request.json
            if not data:
                return jsonify({
                    "status": "error",
                    "message": "Missing request data"
                }), 400
            
            parent_path = data.get("path", "")
            dir_name = data.get("name", "")
            
            if not dir_name:
                return jsonify({
                    "status": "error",
                    "message": "Directory name is required"
                }), 400
            
            # Normalize the path to prevent directory traversal attacks
            full_parent_path = os.path.normpath(os.path.join(base_dir, parent_path))
            
            # Ensure the path is within the base directory
            if not full_parent_path.startswith(base_dir):
                logger.warning(f"Attempted directory traversal: {parent_path}")
                return jsonify({
                    "status": "error",
                    "message": "Invalid directory path"
                }), 403
            
            # Check if the parent path exists and is a directory
            if not os.path.exists(full_parent_path):
                logger.warning(f"Parent path does not exist: {full_parent_path}")
                return jsonify({
                    "status": "error",
                    "message": "Parent directory not found"
                }), 404
            
            if not os.path.isdir(full_parent_path):
                logger.warning(f"Parent path is not a directory: {full_parent_path}")
                return jsonify({
                    "status": "error",
                    "message": "Parent path is not a directory"
                }), 400
            
            # Create the new directory
            new_dir_path = os.path.join(full_parent_path, dir_name)
            if os.path.exists(new_dir_path):
                return jsonify({
                    "status": "error",
                    "message": "Directory already exists"
                }), 409
            
            os.makedirs(new_dir_path, exist_ok=True)
            logger.info(f"Created directory: {new_dir_path}")
            
            # Calculate relative path from base directory
            rel_path = os.path.relpath(new_dir_path, base_dir)
            
            return jsonify({
                "status": "success",
                "message": "Directory created successfully",
                "path": rel_path
            }), 201
            
        except Exception as e:
            logger.error(f"Error in create_directory: {e}", exc_info=True)
            return jsonify({
                "status": "error",
                "message": f"Server error: {str(e)}"
            }), 500
