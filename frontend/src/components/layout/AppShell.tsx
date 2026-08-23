import { Outlet } from 'react-router-dom';
import { Sidebar } from './Sidebar';
import { TopBar } from './TopBar';
import styles from './AppShell.module.css';
export function AppShell() { return <div className={styles.shell}><Sidebar /><main className={styles.main}><TopBar /><div className={styles.content}><Outlet /></div></main></div>; }
