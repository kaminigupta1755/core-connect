import { motion } from "framer-motion";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Shield, AlertTriangle } from "lucide-react";
import { useBossNotifications } from "@/hooks/boss-core";

const LegalAudit = () => {
  const { data, loading } = useBossNotifications("legal", 200);

  return (
    <motion.div initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} className="space-y-6">
      <div className="flex justify-between items-center">
        <div className="flex items-center gap-3">
          <Shield className="h-6 w-6 text-amber-400" />
          <h2 className="text-xl font-semibold text-white">Audit Trail</h2>
        </div>
        <Badge className="bg-slate-700 text-slate-300">Read Only</Badge>
      </div>

      <div className="bg-yellow-500/10 border border-yellow-500/30 rounded-lg p-4 flex items-center gap-3">
        <AlertTriangle className="h-5 w-5 text-yellow-400" />
        <p className="text-yellow-400 text-sm">Immutable audit log streamed from the Boss Notifications channel.</p>
      </div>

      <Card className="bg-slate-900/50 border-slate-700/50">
        <CardHeader><CardTitle className="text-amber-400">Activity Log</CardTitle></CardHeader>
        <CardContent>
          {loading ? (
            <p className="text-slate-400 text-sm py-6 text-center">Loading…</p>
          ) : data.length === 0 ? (
            <p className="text-slate-400 text-sm py-10 text-center border border-dashed border-slate-700 rounded-lg">
              No legal audit events yet.
            </p>
          ) : (
            <Table>
              <TableHeader>
                <TableRow className="border-slate-700">
                  <TableHead className="text-slate-400">Time</TableHead>
                  <TableHead className="text-slate-400">Event</TableHead>
                  <TableHead className="text-slate-400">Severity</TableHead>
                  <TableHead className="text-slate-400">Detail</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {data.map((n) => (
                  <TableRow key={n.id} className="border-slate-700/50">
                    <TableCell className="text-slate-300 font-mono text-xs">{new Date(n.created_at).toLocaleString()}</TableCell>
                    <TableCell className="text-white">{n.title}</TableCell>
                    <TableCell><Badge>{n.severity}</Badge></TableCell>
                    <TableCell className="text-slate-400 text-xs">{n.body ?? "—"}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>
    </motion.div>
  );
};

export default LegalAudit;
