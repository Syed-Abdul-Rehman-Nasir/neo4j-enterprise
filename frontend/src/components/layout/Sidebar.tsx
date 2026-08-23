import { Activity, AppWindow, DatabaseZap, GitBranch, Network, SearchCode } from 'lucide-react';
import { NavLink } from 'react-router-dom';
import styles from './Sidebar.module.css';

const links = [
  { to: '/', label: 'Overview', icon: Activity },
  { to: '/graph', label: 'Graph', icon: Network },
  { to: '/impact', label: 'Impact', icon: DatabaseZap },
  { to: '/applications', label: 'Applications', icon: AppWindow },
  { to: '/operations', label: 'Operations', icon: GitBranch },
  { to: '/queries/q4', label: 'Queries', icon: SearchCode }
];
export function Sidebar() { return <aside className={styles.sidebar}><div className={styles.brand}><div className={styles.logo}>N4</div><div><p className={styles.title}>Topology Signal Room</p><p className={styles.sub}>Enterprise Neo4j Ops</p></div></div><nav className={styles.nav}>{links.map(({ to, label, icon: Icon }) => <NavLink key={to} to={to} end={to === '/'} className={({ isActive }) => `${styles.link} ${isActive ? styles.active : ''}`}><Icon size={18} />{label}</NavLink>)}</nav></aside>; }
