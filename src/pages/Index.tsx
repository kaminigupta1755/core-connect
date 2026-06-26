import { MarketHeader } from "@/components/market/MarketHeader";
import {
  HeroBanner, QuickActions, LiveStats, FeaturedRow, IndustryGrid,
  TrendingRow, BestSellersRow, NewReleasesRow, AIZone, ProductsByCategory,
} from "@/components/market/sections";
import {
  SuccessStories, AwardsWall, LiveFeed, ValaTV, Academy,
  PartnerEcosystem, FAQ, FinalCTA, Footer,
} from "@/components/market/sections-2";
import { CartProvider } from "@/hooks/use-cart";

export default function Index() {
  return (
    <CartProvider>
      <div className="min-h-screen bg-background text-foreground">
        <MarketHeader />
        <main className="max-w-[1600px] mx-auto px-4 lg:px-6 py-6 lg:py-8 space-y-8 lg:space-y-12">
          <HeroBanner />
          <QuickActions />
          <LiveStats />
          <FeaturedRow />
          <IndustryGrid />
          <TrendingRow />
          <BestSellersRow />
          <NewReleasesRow />
          <ProductsByCategory />
          <AIZone />
          <SuccessStories />
          <AwardsWall />
          <LiveFeed />
          <ValaTV />
          <Academy />
          <PartnerEcosystem />
          <FAQ />
          <FinalCTA />
          <Footer />
        </main>
      </div>
    </CartProvider>
  );
}
