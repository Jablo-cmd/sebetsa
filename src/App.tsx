import { BrowserRouter } from 'react-router-dom';
import { ToastProvider } from '@/components/ui/toast/ToastProvider';
import { AuthProvider } from '@/features/auth/context/AuthProvider';
import { ProfileProvider } from '@/features/profile/context/ProfileProvider';
import { TenantProvider } from '@/features/tenant/context/TenantProvider';
import { AppRoutes } from '@/app/AppRoutes';

// Vite's import.meta.env.BASE_URL, minus the trailing slash React Router doesn't want.
const routerBasename = import.meta.env.BASE_URL.replace(/\/$/, '') || '/';

export function App() {
  return (
    <BrowserRouter basename={routerBasename} future={{ v7_startTransition: true, v7_relativeSplatPath: true }}>
      <ToastProvider>
        <AuthProvider>
          <ProfileProvider>
            <TenantProvider>
              <AppRoutes />
            </TenantProvider>
          </ProfileProvider>
        </AuthProvider>
      </ToastProvider>
    </BrowserRouter>
  );
}
