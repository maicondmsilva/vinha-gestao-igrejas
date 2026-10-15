import { UnavailableFeature } from '../../PilotAvailability';

// Do not mount legacy client pages while their operations are unavailable.
export default function ContainedLegacyLayout({ children: _children }: { children: React.ReactNode }) {
  return <UnavailableFeature/>;
}
