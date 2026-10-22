/**
 * College Smart Canteen Token System
 * Client-Side Interaction & Modal Handling
 */

document.addEventListener('DOMContentLoaded', function () {
    initLiveClock();
    initSidebarToggle();
    initRegistrationForm();
    initAutoDismissToasts();
});

/**
 * Live Clock in Topbar
 */
function initLiveClock() {
    const clockEl = document.getElementById('liveClock');
    if (!clockEl) return;

    function updateClock() {
        const now = new Date();
        const hours = String(now.getHours()).padStart(2, '0');
        const minutes = String(now.getMinutes()).padStart(2, '0');
        const seconds = String(now.getSeconds()).padStart(2, '0');
        clockEl.textContent = `${hours}:${minutes}:${seconds}`;
    }

    updateClock();
    setInterval(updateClock, 1000);
}

/**
 * Mobile Sidebar Drawer
 */
function initSidebarToggle() {
    const sidebar = document.getElementById('appSidebar');
    const toggleBtn = document.getElementById('sidebarToggleBtn');
    const closeBtn = document.getElementById('sidebarCloseBtn');

    if (toggleBtn && sidebar) {
        toggleBtn.addEventListener('click', function () {
            sidebar.classList.toggle('sidebar-open');
        });
    }

    if (closeBtn && sidebar) {
        closeBtn.addEventListener('click', function () {
            sidebar.classList.remove('sidebar-open');
        });
    }
}

/**
 * Auto-Dismiss Flash Toasts after 5 seconds
 */
function initAutoDismissToasts() {
    const toasts = document.querySelectorAll('.toast');
    toasts.forEach(toast => {
        setTimeout(() => {
            if (toast && toast.parentElement) {
                toast.style.transition = 'opacity 0.4s ease, transform 0.4s ease';
                toast.style.opacity = '0';
                toast.style.transform = 'translateY(-10px)';
                setTimeout(() => toast.remove(), 400);
            }
        }, 5500);
    });
}

/**
 * Customer Registration Form Double-Submission Prevention & Validation
 */
function initRegistrationForm() {
    const form = document.getElementById('registerForm');
    if (!form) return;

    const nameInput = document.getElementById('fullName');
    const nameError = document.getElementById('nameError');
    const submitBtn = document.getElementById('submitRegisterBtn');
    const spinner = document.getElementById('registerSpinner');
    const btnText = document.getElementById('registerBtnText');

    form.addEventListener('submit', function (event) {
        const trimmedName = nameInput.value.trim();

        if (!trimmedName || trimmedName.length < 2) {
            event.preventDefault();
            nameInput.classList.add('is-invalid');
            if (nameError) nameError.style.display = 'block';
            nameInput.focus();
            return false;
        }

        // Clean trimmed value into input
        nameInput.value = trimmedName;

        // Prevent Double Submission
        if (submitBtn.dataset.submitting === 'true') {
            event.preventDefault();
            return false;
        }

        submitBtn.dataset.submitting = 'true';
        submitBtn.disabled = true;

        if (spinner) spinner.style.display = 'inline-block';
        if (btnText) btnText.textContent = 'Allocating in MySQL...';

        // Submit form programmatically
        form.submit();
    });

    if (nameInput) {
        nameInput.addEventListener('input', function () {
            if (nameInput.value.trim().length >= 2) {
                nameInput.classList.remove('is-invalid');
                if (nameError) nameError.style.display = 'none';
            }
        });
    }
}

/**
 * Confirm Delivery Action Modal / Dialog
 * Used by Active Tokens table rows.
 */
let pendingDeliveryForm = null;

function confirmDelivery(event, tokenNumber, customerName) {
    event.preventDefault();
    const form = event.target;

    const modal = document.getElementById('confirmModal');
    const modalTitle = document.getElementById('modalTitle');
    const modalMessage = document.getElementById('modalMessage');
    const modalConfirmBtn = document.getElementById('modalConfirmBtn');
    const modalCancelBtn = document.getElementById('modalCancelBtn');
    const modalCancelCross = document.getElementById('modalCancelBtnCross');

    if (!modal) {
        // Fallback to standard native confirmation
        const confirmed = window.confirm(
            `Mark Token #${tokenNumber} (${customerName}) as Delivered?\n\nThis will complete the order and promote the next waiting customer (if any).`
        );
        if (confirmed) {
            form.submit();
        }
        return false;
    }

    pendingDeliveryForm = form;
    modalTitle.textContent = `Deliver Token #${tokenNumber}?`;
    modalMessage.innerHTML = `
        <p>Are you sure you want to mark the order for <strong>${customerName}</strong> (Token #${tokenNumber}) as delivered?</p>
        <p class="small text-muted mt-2">
            This will execute stored procedure <code>sp_complete_order</code>, archive the token into order history, and automatically promote the first waiting customer to Token #${tokenNumber}.
        </p>
    `;
    modalConfirmBtn.textContent = 'Yes, Mark Delivered';
    modalConfirmBtn.className = 'btn btn-success';

    modal.style.display = 'flex';

    function closeModal() {
        modal.style.display = 'none';
        pendingDeliveryForm = null;
    }

    modalCancelBtn.onclick = closeModal;
    modalCancelCross.onclick = closeModal;

    modalConfirmBtn.onclick = function () {
        if (pendingDeliveryForm) {
            modalConfirmBtn.disabled = true;
            modalConfirmBtn.textContent = 'Delivering...';
            pendingDeliveryForm.submit();
        }
        closeModal();
    };

    return false;
}
