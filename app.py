import secrets
from datetime import datetime
from flask import (
    Flask,
    render_template,
    request,
    redirect,
    url_for,
    flash,
    session,
    abort,
    jsonify,
)
from config import Config
import db

app = Flask(__name__)
app.config.from_object(Config)


# ============================================================================
# CSRF PROTECTION & SECURITY HELPERS
# ============================================================================

def generate_csrf_token() -> str:
    """Generates and stores a cryptographically secure CSRF token in the user session."""
    if "csrf_token" not in session:
        session["csrf_token"] = secrets.token_hex(32)
    return session["csrf_token"]


@app.before_request
def csrf_protect():
    """Validates CSRF token on all state-changing POST requests."""
    if request.method == "POST":
        token = request.form.get("csrf_token")
        expected_token = session.get("csrf_token")
        if not token or not expected_token or not secrets.compare_digest(token, expected_token):
            abort(400, description="Invalid or expired CSRF token. Please refresh and try again.")


@app.context_processor
def inject_global_template_vars():
    """Injects CSRF helper and dynamic sidebar badges into all templates."""
    token = generate_csrf_token()

    active_count = 0
    waiting_count = 0
    try:
        summary = db.get_dashboard_summary()
        active_count = summary.get("active_tokens", 0)
        waiting_count = summary.get("customers_waiting", 0)
    except Exception:
        # Avoid crashing global template rendering during DB downtime
        pass

    return {
        "csrf_token": lambda: token,
        "nav_active_count": active_count,
        "nav_waiting_count": waiting_count,
        "current_year": datetime.now().year,
    }


# ============================================================================
# ERROR HANDLERS
# ============================================================================

@app.errorhandler(db.DatabaseConnectionError)
def handle_db_connection_error(error):
    """Graceful, friendly error page when MySQL cannot be reached."""
    return (
        render_template(
            "error.html",
            is_db_error=True,
            error_code=503,
            error_message=str(error),
        ),
        503,
    )


@app.errorhandler(db.DatabaseQueryError)
def handle_db_query_error(error):
    """Handles SQL and stored procedure query exceptions."""
    return (
        render_template(
            "error.html",
            is_db_error=False,
            error_code=500,
            error_message=str(error),
        ),
        500,
    )


@app.errorhandler(400)
def handle_bad_request(error):
    return (
        render_template(
            "error.html",
            is_db_error=False,
            error_code=400,
            error_message=getattr(error, "description", "Bad Request"),
        ),
        400,
    )


@app.errorhandler(404)
def handle_not_found(error):
    return (
        render_template(
            "error.html",
            is_db_error=False,
            error_code=404,
            error_message="The requested canteen page or resource does not exist.",
        ),
        404,
    )


@app.errorhandler(500)
def handle_internal_error(error):
    return (
        render_template(
            "error.html",
            is_db_error=False,
            error_code=500,
            error_message="An unexpected server error occurred. Please contact the canteen administrator.",
        ),
        500,
    )


# ============================================================================
# APPLICATION ROUTES (PAGES)
# ============================================================================

@app.route("/")
def dashboard():
    """
    Page 1: Dashboard
    Shows cards for active tokens (x/15), available slots, waiting, completed today
    from v_dashboard_summary. Displays FULL CAPACITY banner when active = 15.
    """
    summary = db.get_dashboard_summary()
    active_tokens = db.get_active_tokens()
    waiting_list = db.get_waiting_queue()

    return render_template(
        "dashboard.html",
        active_page="dashboard",
        summary=summary,
        active_tokens=active_tokens,
        waiting_list=waiting_list,
    )


@app.route("/register", methods=["GET", "POST"])
def register_customer():
    """
    Page 2: Register Customer
    Name (required, 2-100 chars) and optional roll number.
    Calls sp_generate_token, shows assigned token or waiting queue number.
    Prevents double submission.
    """
    summary = db.get_dashboard_summary()
    registration_result = None
    prev_name = ""
    prev_roll = ""

    if request.method == "POST":
        full_name = request.form.get("full_name", "").strip()
        roll_number = request.form.get("roll_number", "").strip()
        prev_name = full_name
        prev_roll = roll_number

        # Server-side validation
        if not full_name or len(full_name) < 2 or len(full_name) > 100:
            flash("Customer name is required and must be between 2 and 100 characters.", "danger")
        else:
            # Call MySQL stored procedure sp_generate_token
            res = db.call_sp_generate_token(full_name, roll_number or None)
            registration_result = res

            status = res.get("status")
            if status == "ACTIVE":
                flash(
                    f"Success! Order #{res.get('order_id')} assigned ACTIVE Token #{res.get('token_number')}.",
                    "success",
                )
                # Clear fields on success
                prev_name = ""
                prev_roll = ""
            elif status == "WAITING":
                flash(
                    f"Canteen full! Customer added to WAITING list at Queue #{res.get('queue_number')} (Order #{res.get('order_id')}).",
                    "warning",
                )
                prev_name = ""
                prev_roll = ""
            else:
                flash(f"Registration rejected: {res.get('message')}", "danger")

            # Refresh summary after procedure execution
            summary = db.get_dashboard_summary()

    return render_template(
        "register.html",
        active_page="register",
        summary=summary,
        registration_result=registration_result,
        prev_name=prev_name,
        prev_roll=prev_roll,
    )


@app.route("/active-tokens")
def active_tokens_view():
    """
    Page 3: Active Tokens
    Displays v_active_tokens table with a 'Mark as Delivered' button.
    """
    active_tokens = db.get_active_tokens()
    return render_template(
        "active_tokens.html",
        active_page="active_tokens",
        active_tokens=active_tokens,
    )


@app.route("/orders/<int:order_id>/complete", methods=["POST"])
def complete_order_action(order_id: int):
    """
    State Action: Mark an order as delivered.
    Calls MySQL stored procedure sp_complete_order(p_order_id, OUT ...).
    Handles result (COMPLETED, REJECTED, NOT_FOUND) and waiting customer promotion.
    """
    res = db.call_sp_complete_order(order_id)
    result = res.get("result")
    message = res.get("message", "")
    promoted_order_id = res.get("promoted_order_id")
    promoted_token = res.get("promoted_token")

    if result == "COMPLETED":
        if promoted_order_id:
            flash(
                f"Order #{order_id} marked as DELIVERED! Waiting Order #{promoted_order_id} was automatically promoted to Token #{promoted_token}.",
                "success",
            )
        else:
            flash(f"Order #{order_id} marked as DELIVERED! {message}", "success")
    elif result == "REJECTED":
        flash(f"Action Rejected: {message}", "warning")
    elif result == "NOT_FOUND":
        flash("Action Failed: Order not found in database.", "danger")
    else:
        flash(f"Delivery update: {message}", "info")

    # Redirect back to the referring page or default to active tokens
    referrer = request.referrer
    if referrer and ("active-tokens" in referrer or "dashboard" in referrer or "/" == referrer):
        return redirect(referrer)
    return redirect(url_for("active_tokens_view"))


@app.route("/waiting-list")
def waiting_list_view():
    """
    Page 4: Waiting List
    Displays v_waiting_queue (queue position, name, order ID, waiting time, status), oldest first.
    """
    waiting_queue = db.get_waiting_queue()
    return render_template(
        "waiting_list.html",
        active_page="waiting_list",
        waiting_queue=waiting_queue,
    )


@app.route("/history")
def order_history_view():
    """
    Page 5: Order History
    Displays v_order_history with name search and date filter.
    """
    search_name = request.args.get("q", "").strip()
    filter_date = request.args.get("date", "").strip()

    history_records = db.get_order_history(
        search_name=search_name if search_name else None,
        filter_date=filter_date if filter_date else None,
    )

    return render_template(
        "history.html",
        active_page="history",
        history_records=history_records,
        search_name=search_name,
        filter_date=filter_date,
    )


@app.route("/reports")
def reports_view():
    """
    Page 6: Reports & Analytics
    Displays v_daily_report plus Chart.js charts using real database data only.
    """
    daily_reports = db.get_daily_report()

    # Prepare sanitized JSON dataset for Chart.js (chronological order)
    reports_chronological = list(reversed(daily_reports))
    labels = [str(r.get("business_date")) for r in reports_chronological]
    registered = [int(r.get("total_registered") or 0) for r in reports_chronological]
    completed = [int(r.get("total_completed") or 0) for r in reports_chronological]
    avg_minutes = [
        float(r.get("avg_completion_minutes") or 0.0) for r in reports_chronological
    ]
    peak_tokens = [int(r.get("peak_active_tokens") or 0) for r in reports_chronological]

    chart_payload = {
        "labels": labels,
        "registered": registered,
        "completed": completed,
        "avgMinutes": avg_minutes,
        "peakTokens": peak_tokens,
    }

    return render_template(
        "reports.html",
        active_page="reports",
        daily_reports=daily_reports,
        chart_payload=chart_payload,
    )


@app.route("/ping")
@app.route("/healthz")
def ping():
    """Simple ping route for cloud health checkers."""
    return "OK", 200


@app.route("/api/health")
def api_health():
    """Diagnostic health check endpoint verifying MySQL connectivity."""
    success, message = db.test_db_connection()
    status_code = 200 if success else 503
    return jsonify({
        "status": "connected" if success else "disconnected",
        "message": message,
        "database": Config.DB_NAME,
        "host": Config.DB_HOST,
        "port": Config.DB_PORT,
    }), status_code


# ============================================================================
# SERVER STARTUP
# ============================================================================

if __name__ == "__main__":
    print(f"Starting College Smart Canteen on http://127.0.0.1:5000")
    print(f"Connecting to MySQL database '{Config.DB_NAME}' at {Config.DB_HOST}:{Config.DB_PORT} as '{Config.DB_USER}'")
    app.run(host="127.0.0.1", port=5000, debug=Config.DEBUG)
