import React, { useState } from 'react';
import { Heart, Volume2, Eye, Upload, Home, Search, Wallet, MoreHorizontal, Tv } from 'lucide-react';

const RetroArchiveUI = () => {
  const [isLiked, setIsLiked] = useState(false);
  const [isMuted, setIsMuted] = useState(false);

  return (
    <div className="min-h-screen bg-black text-gray-200">
      {/* Main Content Area */}
      <div className="relative h-screen">
        {/* Top Status Bar */}
        <div className="flex justify-between items-center p-4 bg-black bg-opacity-50">
          <span className="font-mono text-green-500">9:00</span>
          <div className="flex items-center gap-2">
            <span className="font-mono text-green-500">77%</span>
          </div>
        </div>

        {/* Video Container */}
        <div className="relative w-full h-3/4 bg-gray-900">
          {/* Vintage TV Frame Overlay */}
          <div className="absolute inset-0 border-t-[40px] border-b-[40px] border-l-[20px] border-r-[20px] border-gray-800 rounded-lg pointer-events-none">
            <div className="absolute top-[-30px] left-4 w-8 h-8 bg-gray-700 rounded-full"></div>
            <div className="absolute top-[-30px] left-16 w-8 h-8 bg-gray-700 rounded-full"></div>
          </div>

          {/* Placeholder for video content */}
          <div className="absolute inset-0 flex items-center justify-center">
            <div className="w-16 h-16 bg-gray-800 rounded-full flex items-center justify-center">
              <div className="w-8 h-8 bg-white"></div>
            </div>
          </div>

          {/* Video Progress Bar */}
          <div className="absolute bottom-0 w-full h-1 bg-gray-800">
            <div className="w-1/3 h-full bg-green-500"></div>
          </div>
        </div>

        {/* Interaction Buttons */}
        <div className="absolute right-4 bottom-20 flex flex-col items-center gap-6">
          <button 
            onClick={() => setIsLiked(!isLiked)} 
            className={`p-2 rounded-full ${isLiked ? 'text-red-500' : 'text-white'} hover:bg-gray-800`}
          >
            <Heart className={`w-8 h-8 ${isLiked ? 'fill-current' : ''}`} />
          </button>
          <button 
            onClick={() => setIsMuted(!isMuted)}
            className="p-2 rounded-full text-white hover:bg-gray-800"
          >
            <Volume2 className="w-8 h-8" />
          </button>
          <div className="flex flex-col items-center">
            <Eye className="w-8 h-8" />
            <span className="text-sm">0</span>
          </div>
        </div>

        {/* Video Info */}
        <div className="p-4">
          <h2 className="font-mono text-green-500">Horror Movie Trailers, 1970s</h2>
          <p className="text-gray-400">#archive</p>
        </div>

        {/* Bottom Navigation */}
        <div className="fixed bottom-0 w-full bg-gray-900 border-t border-gray-800">
          <div className="flex justify-around items-center p-4">
            <button className="flex flex-col items-center text-green-500">
              <Tv className="w-6 h-6" />
              <span className="text-xs mt-1">Archive</span>
            </button>
            <button className="flex flex-col items-center text-gray-500">
              <Home className="w-6 h-6" />
              <span className="text-xs mt-1">Home</span>
            </button>
            <button className="flex flex-col items-center text-gray-500">
              <Search className="w-6 h-6" />
              <span className="text-xs mt-1">Search</span>
            </button>
            <button className="flex flex-col items-center text-gray-500">
              <Wallet className="w-6 h-6" />
              <span className="text-xs mt-1">Wallet</span>
            </button>
            <button className="flex flex-col items-center text-gray-500">
              <MoreHorizontal className="w-6 h-6" />
              <span className="text-xs mt-1">More</span>
            </button>
          </div>
        </div>
      </div>
    </div>
  );
};

export default RetroArchiveUI;
