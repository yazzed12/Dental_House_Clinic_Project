import Sidebar from './Sidebar';
import Topbar from './Topbar';

export default function Layout({ children, pageTitle, pageSubtitle }) {
  return (
    <div className="app-layout">
      <Sidebar />
      <div className="main-content">
        <Topbar pageTitle={pageTitle} pageSubtitle={pageSubtitle} />
        <main className="page-body">
          {children}
        </main>
      </div>
    </div>
  );
}
