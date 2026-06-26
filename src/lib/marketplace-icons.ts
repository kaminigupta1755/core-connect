import {
  Factory, BarChart3, GraduationCap, Stethoscope, ShoppingCart, Briefcase,
  BrainCircuit, Workflow, Banknote, HardHat, Truck, Hotel, Home, Scale,
  Landmark, Sparkles, HeartHandshake, Cpu, ShieldCheck, TrendingUp,
  Headset, KeyRound, Heart, Award, Globe2,
} from "lucide-react";

const map: Record<string, React.ComponentType<React.SVGProps<SVGSVGElement>>> = {
  Factory, BarChart3, GraduationCap, Stethoscope, ShoppingCart, Briefcase,
  BrainCircuit, Workflow, Banknote, HardHat, Truck, Hotel, Home, Scale,
  Landmark, Sparkles, HeartHandshake, Cpu, ShieldCheck, TrendingUp,
  Headset, KeyRound, Heart, Award, Globe2,
};

export function resolveIcon(name: string | null | undefined) {
  if (!name) return Briefcase;
  return map[name] ?? Briefcase;
}
