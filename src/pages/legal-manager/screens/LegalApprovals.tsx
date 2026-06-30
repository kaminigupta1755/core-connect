import { motion } from "framer-motion";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Check, X } from "lucide-react";
import { toast } from "sonner";
import { useBossApprovals } from "@/hooks/boss-core";

const LegalApprovals = () => {
  const { data, loading, approve, reject } = useBossApprovals({ module: "legal" });

  const handle = async (id: string, ok: boolean) => {
    const { error } = ok ? await approve(id) : await reject(id);
    if (error) toast.error(error.message);
    else toast.success(ok ? "Approved" : "Rejected");
  };

  const pending = data.filter((a) => a.status === "pending");

  return (
    <motion.div initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} className="space-y-6">
      <div className="flex justify-between items-center">
        <h2 className="text-xl font-semibold text-white">Approvals</h2>
        <Badge className="bg-yellow-500/20 text-yellow-400">{pending.length} Pending</Badge>
      </div>
      <Card className="bg-slate-900/50 border-slate-700/50">
        <CardHeader><CardTitle className="text-amber-400">Approval Queue</CardTitle></CardHeader>
        <CardContent>
          {loading ? (
            <p className="text-slate-400 text-sm py-6 text-center">Loading…</p>
          ) : data.length === 0 ? (
            <p className="text-slate-400 text-sm py-10 text-center border border-dashed border-slate-700 rounded-lg">
              No legal approvals yet. Requests appear here in real time as modules dispatch them.
            </p>
          ) : (
            <Table>
              <TableHeader>
                <TableRow className="border-slate-700">
                  <TableHead className="text-slate-400">Item</TableHead>
                  <TableHead className="text-slate-400">Requested By</TableHead>
                  <TableHead className="text-slate-400">Action Key</TableHead>
                  <TableHead className="text-slate-400">Status</TableHead>
                  <TableHead className="text-slate-400">Actions</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {data.map((a) => (
                  <TableRow key={a.id} className="border-slate-700/50">
                    <TableCell className="text-white font-medium">{a.title}</TableCell>
                    <TableCell className="text-slate-300 font-mono text-xs">{a.requested_by_role ?? "—"}</TableCell>
                    <TableCell className="text-slate-300 font-mono text-xs">{a.action_key}</TableCell>
                    <TableCell><Badge>{a.status}</Badge></TableCell>
                    <TableCell>
                      {a.status === "pending" && (
                        <div className="flex gap-2">
                          <Button size="sm" className="bg-emerald-600 hover:bg-emerald-700" onClick={() => handle(a.id, true)}><Check className="h-4 w-4" /></Button>
                          <Button size="sm" variant="destructive" onClick={() => handle(a.id, false)}><X className="h-4 w-4" /></Button>
                        </div>
                      )}
                    </TableCell>
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

export default LegalApprovals;
