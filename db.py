import logging
from contextlib import contextmanager
from typing import Any, Dict, List, Optional
import mysql.connector
from mysql.connector import Error, errorcode
from config import Config

logger = logging.getLogger(__name__)


class DatabaseConnectionError(Exception):
    """Raised when application cannot establish a connection to MySQL."""
    def __init__(self, message: str, original_error: Optional[Exception] = None):
        super().__init__(message)
        self.original_error = original_error


class DatabaseQueryError(Exception):
    """Raised when a query or stored procedure fails."""
    def __init__(self, message: str, original_error: Optional[Exception] = None):
        super().__init__(message)
        self.original_error = original_error


@contextmanager
def get_db():
    """
    Context manager providing a MySQL database connection.
    Guarantees rollback on error and proper connection closing.
    """
    conn = None
    try:
        conn = mysql.connector.connect(**Config.get_db_config())
        yield conn
    except mysql.connector.Error as err:
        if err.errno in (
            errorcode.CR_CONN_HOST_ERROR,
            errorcode.CR_CONNECTION_ERROR,
            errorcode.ER_ACCESS_DENIED_ERROR,
            errorcode.ER_BAD_DB_ERROR,
            2003, 1045, 1049
        ):
            logger.error("Database connection failure: %s", err)
            raise DatabaseConnectionError(
                f"Could not connect to MySQL server at {Config.DB_HOST}:{Config.DB_PORT}. "
                f"Error: {err.msg} (Code: {err.errno})",
                original_error=err
            ) from err
        logger.error("MySQL Error: %s", err)
        raise DatabaseQueryError(f"Database error: {err.msg}", original_error=err) from err
    finally:
        if conn is not None and conn.is_connected():
            try:
                conn.close()
            except Exception as close_err:
                logger.warning("Error closing MySQL connection: %s", close_err)


def test_db_connection() -> tuple[bool, str]:
    """
    Verifies if database connection succeeds and database exists.
    Returns (success: bool, message: str).
    """
    try:
        with get_db() as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT 1")
            cursor.fetchone()
            cursor.close()
            return True, "Database connection successful."
    except DatabaseConnectionError as e:
        return False, str(e)
    except Exception as e:
        return False, f"Unexpected error while connecting to database: {e}"


def get_dashboard_summary() -> Dict[str, Any]:
    """
    Reads summary stats from v_dashboard_summary view.
    Returns dict: active_tokens, available_slots, max_active_tokens,
                  customers_waiting, completed_today.
    """
    with get_db() as conn:
        cursor = conn.cursor(dictionary=True)
        try:
            cursor.execute("SELECT * FROM v_dashboard_summary LIMIT 1")
            row = cursor.fetchone()
            if not row:
                return {
                    "active_tokens": 0,
                    "available_slots": 15,
                    "max_active_tokens": 15,
                    "customers_waiting": 0,
                    "completed_today": 0,
                }
            return {
                "active_tokens": int(row.get("active_tokens") or 0),
                "available_slots": int(row.get("available_slots") or 0),
                "max_active_tokens": int(row.get("max_active_tokens") or 15),
                "customers_waiting": int(row.get("customers_waiting") or 0),
                "completed_today": int(row.get("completed_today") or 0),
            }
        finally:
            cursor.close()


def get_active_tokens() -> List[Dict[str, Any]]:
    """
    Reads active tokens from v_active_tokens view ordered by token_number.
    """
    with get_db() as conn:
        cursor = conn.cursor(dictionary=True)
        try:
            cursor.execute("SELECT * FROM v_active_tokens ORDER BY token_number ASC")
            return cursor.fetchall()
        finally:
            cursor.close()


def get_waiting_queue() -> List[Dict[str, Any]]:
    """
    Reads waiting customers from v_waiting_queue view in FIFO order.
    """
    with get_db() as conn:
        cursor = conn.cursor(dictionary=True)
        try:
            cursor.execute("SELECT * FROM v_waiting_queue ORDER BY queue_position ASC")
            return cursor.fetchall()
        finally:
            cursor.close()


def get_order_history(search_name: Optional[str] = None, filter_date: Optional[str] = None) -> List[Dict[str, Any]]:
    """
    Reads order history from v_order_history with parameterized name search and date filter.
    """
    query = "SELECT * FROM v_order_history WHERE 1=1"
    params: List[Any] = []

    if search_name and search_name.strip():
        query += " AND full_name LIKE %s"
        params.append(f"%{search_name.strip()}%")

    if filter_date and filter_date.strip():
        query += " AND business_date = %s"
        params.append(filter_date.strip())

    query += " ORDER BY completed_at DESC"

    with get_db() as conn:
        cursor = conn.cursor(dictionary=True)
        try:
            cursor.execute(query, tuple(params))
            return cursor.fetchall()
        finally:
            cursor.close()


def get_daily_report() -> List[Dict[str, Any]]:
    """
    Reads daily aggregates from v_daily_report view ordered by business_date DESC.
    """
    with get_db() as conn:
        cursor = conn.cursor(dictionary=True)
        try:
            cursor.execute("SELECT * FROM v_daily_report ORDER BY business_date DESC")
            return cursor.fetchall()
        finally:
            cursor.close()


def call_sp_generate_token(full_name: str, roll_number: Optional[str] = None) -> Dict[str, Any]:
    """
    Calls stored procedure sp_generate_token with OUT parameters:
      p_full_name, p_roll_number,
      OUT p_order_id, OUT p_status, OUT p_token_number, OUT p_queue_number, OUT p_message
    Returns dict:
      {
        'order_id': int or None,
        'status': 'ACTIVE' | 'WAITING' | 'REJECTED',
        'token_number': int or None,
        'queue_number': int or None,
        'message': str
      }
    """
    name_clean = (full_name or "").strip()
    roll_clean = (roll_number or "").strip() or None

    with get_db() as conn:
        cursor = conn.cursor()
        try:
            # Arguments for sp_generate_token:
            # (IN p_full_name, IN p_roll_number, OUT p_order_id, OUT p_status,
            #  OUT p_token_number, OUT p_queue_number, OUT p_message)
            args = (name_clean, roll_clean, 0, "", 0, 0, "")
            res = cursor.callproc("sp_generate_token", args)
            conn.commit()

            # mysql-connector-python returns the result row as a tuple or dict
            if isinstance(res, dict):
                vals = list(res.values())
            else:
                vals = list(res)

            # Map the OUT parameters (indices 2 to 6)
            order_id = vals[2] if vals[2] is not None and vals[2] != 0 else None
            status = str(vals[3]) if vals[3] else "REJECTED"
            token_number = vals[4] if vals[4] is not None and vals[4] != 0 else None
            queue_number = vals[5] if vals[5] is not None and vals[5] != 0 else None
            message = str(vals[6]) if vals[6] else ""

            return {
                "order_id": order_id,
                "status": status,
                "token_number": token_number,
                "queue_number": queue_number,
                "message": message,
            }
        except Exception as e:
            conn.rollback()
            logger.error("Error executing sp_generate_token: %s", e)
            raise DatabaseQueryError(f"Failed to generate token: {e}", original_error=e) from e
        finally:
            cursor.close()


def call_sp_complete_order(order_id: int) -> Dict[str, Any]:
    """
    Calls stored procedure sp_complete_order with OUT parameters:
      p_order_id,
      OUT p_result, OUT p_message, OUT p_promoted_order_id, OUT p_promoted_token
    Returns dict:
      {
        'result': 'COMPLETED' | 'REJECTED' | 'NOT_FOUND',
        'message': str,
        'promoted_order_id': int or None,
        'promoted_token': int or None
      }
    """
    with get_db() as conn:
        cursor = conn.cursor()
        try:
            # Arguments for sp_complete_order:
            # (IN p_order_id, OUT p_result, OUT p_message, OUT p_promoted_order_id, OUT p_promoted_token)
            args = (order_id, "", "", 0, 0)
            res = cursor.callproc("sp_complete_order", args)
            conn.commit()

            if isinstance(res, dict):
                vals = list(res.values())
            else:
                vals = list(res)

            # Map the OUT parameters (indices 1 to 4)
            result = str(vals[1]) if vals[1] else "REJECTED"
            message = str(vals[2]) if vals[2] else ""
            promoted_order_id = vals[3] if vals[3] is not None and vals[3] != 0 else None
            promoted_token = vals[4] if vals[4] is not None and vals[4] != 0 else None

            return {
                "result": result,
                "message": message,
                "promoted_order_id": promoted_order_id,
                "promoted_token": promoted_token,
            }
        except Exception as e:
            conn.rollback()
            logger.error("Error executing sp_complete_order: %s", e)
            raise DatabaseQueryError(f"Failed to complete order: {e}", original_error=e) from e
        finally:
            cursor.close()
