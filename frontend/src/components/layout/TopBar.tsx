import styles from './TopBar.module.css';
export function TopBar() { return <header className={styles.topbar}><input className={styles.search} aria-label="Search topology" placeholder="Search nodes, apps, databases, incidents..." /><div className={styles.status}><span className={styles.dot} />Live API /api/v1</div></header>; }
